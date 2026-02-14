package main

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strconv"
	"time"

	"github.com/ParkWardRR/PromptHarbor/pkg/config"
	"github.com/ParkWardRR/PromptHarbor/pkg/ssh"
	"github.com/ParkWardRR/PromptHarbor/pkg/vast"
)

var (
	apiKey   = flag.String("api-key", "", "Vast.ai API Key (default: env VAST_API_KEY or ~/.config/promptharbor/vast_api_key)")
	gpuModel = flag.String("gpu", "RTX_5090", "GPU model to search for")
	maxPrice = flag.Float64("price", 0.50, "Max $/hr")
	diskGB   = flag.Float64("disk", 60.0, "Disk size in GB")
	image    = flag.String("image", "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime", "Docker image")

	// Orchestration flags
	controllerURL = flag.String("controller", "", "Controller URL (e.g. http://my-ip:8080)")
	gcsBucket     = flag.String("gcs", "ph-test-2026", "GCS Bucket for outputs")
	credsPath     = flag.String("creds", "", "Path to Google Service Account JSON (default: ~/.config/promptharbor/gcp-sa-key.json)")
	tunnel        = flag.Bool("tunnel", false, "Auto-connect SSH tunnel and stream logs")
	bundleURI     = flag.String("bundle", "", "Optional: PromptHarbor Bundle URI (stateless execution)")
	scriptName    = flag.String("script", "provision.sh", "GCS script to execute (e.g. vast_benchmark.sh)")
)

func main() {
	flag.Parse()

	// Load config (picks up keys from ~/.config/promptharbor/)
	cfg, _ := config.Load("config.yaml")

	// Resolve API key: flag > env > config (which checks key files)
	if *apiKey == "" {
		*apiKey = cfg.VastAI.APIKey
	}
	if *apiKey == "" {
		log.Fatal("VAST_API_KEY is required (set via -api-key, env var, or ~/.config/promptharbor/vast_api_key)")
	}

	// Resolve GCP creds: flag > config
	if *credsPath == "" && cfg.GCP.CredsPath != "" {
		*credsPath = cfg.GCP.CredsPath
	}

	client := vast.NewClient(*apiKey)
	cmd := flag.Arg(0)

	switch cmd {
	case "search":
		{
			offers, err := client.SearchOffers(*gpuModel, *maxPrice, *diskGB)
			if err != nil {
				log.Fatalf("Search failed: %v", err)
			}
			fmt.Printf("Found %d offers for %s (max $%.2f/hr)\n", len(offers), *gpuModel, *maxPrice)
			for i, o := range offers {
				if i >= 10 {
					break
				}
				fmt.Printf("[%d] ID: %d | GPU: %s | $%.3f/hr | Reliability: %.0f%%\n",
					i+1, o.ID, o.GpuName, o.DphTotal, o.Reliability*100)
			}
		}

	case "launch":
		{
			fmt.Printf("Searching for best %s offer...\n", *gpuModel)
			offers, err := client.SearchOffers(*gpuModel, *maxPrice, *diskGB)
			if err != nil {
				log.Fatalf("Search failed: %v", err)
			}
			if len(offers) == 0 {
				log.Fatalf("No offers found matching criteria.")
			}

			best := offers[0]
			fmt.Printf("Selected Offer ID: %d | Host: %d | $%.3f/hr\n", best.ID, best.HostID, best.DphTotal)

			// Prepare OnStart script — must stay under Vast's 4048 char limit
			// Strategy: upload provision script to GCS, onstart is a tiny bootstrap
			envVars := ""
			if *controllerURL != "" {
				envVars += fmt.Sprintf("export CONTROLLER_URL='%s'\n", *controllerURL)
			}
			if *bundleURI != "" {
				envVars += fmt.Sprintf("export BUNDLE_URI='%s'\n", *bundleURI)
				if *credsPath == "" {
					log.Println("⚠️  WARNING: Bundle Mode typically requires -creds for GCS access.")
				}
			}
			if *gcsBucket != "" {
				envVars += fmt.Sprintf("export GCS_BUCKET='%s'\n", *gcsBucket)
			}
			if *credsPath != "" {
				// Compress key to reduce size (saves ~50% vs raw base64)
				data, err := os.ReadFile(*credsPath)
				if err != nil {
					log.Fatalf("Failed to read creds file: %v", err)
				}

				var buf bytes.Buffer
				gz := gzip.NewWriter(&buf)
				gz.Write(data)
				gz.Close()
				b64 := base64.StdEncoding.EncodeToString(buf.Bytes())
				envVars += fmt.Sprintf("export GCP_KEY_GZ='%s'\n", b64)
				fmt.Printf("Creds injected: %d bytes (gzipped from %d)\n", len(b64), len(data))
			}

			// Pass CivitAI key if available
			if cfg.CivitAI.APIKey != "" {
				envVars += fmt.Sprintf("export CIVITAI_API_KEY='%s'\n", cfg.CivitAI.APIKey)
				fmt.Println("CivitAI key injected")
			}
			// Pass HuggingFace token if available
			if cfg.HuggingFace.Token != "" {
				envVars += fmt.Sprintf("export HF_TOKEN='%s'\n", cfg.HuggingFace.Token)
				fmt.Println("HuggingFace token injected")
			}

			// Build compact bootstrap: set env vars → download real script from GCS → execute
			scriptURL := fmt.Sprintf("https://storage.googleapis.com/%s/scripts/%s", *gcsBucket, *scriptName)
			fullScript := "#!/bin/bash\n" + envVars +
				"apt-get update -qq && apt-get install -y -qq curl > /dev/null 2>&1\n" +
				fmt.Sprintf("curl -sL '%s' -o /tmp/provision.sh\n", scriptURL) +
				"chmod +x /tmp/provision.sh\n" +
				"exec /tmp/provision.sh\n"

			fmt.Printf("Bootstrap script: %d chars (Vast limit: 4048)\n", len(fullScript))

			// Try top offers with boot timeout — auto-destroy stuck instances
			var inst *vast.Instance
			var sshHost string
			var sshPort int
			maxTries := 5
			if maxTries > len(offers) {
				maxTries = len(offers)
			}
			bootTimeout := 3 * time.Minute
			seenHosts := map[int]bool{} // skip hosts that already failed

			for i := 0; i < maxTries; i++ {
				pick := offers[i]
				if seenHosts[pick.HostID] {
					fmt.Printf("  Skipping offer %d (host %d already failed)\n", pick.ID, pick.HostID)
					continue
				}
				seenHosts[pick.HostID] = true

				fmt.Printf("Launching offer #%d (ID: %d, host: %d, $%.3f/hr)...\n", i+1, pick.ID, pick.HostID, pick.DphTotal)
				inst2, err := client.LaunchInstance(pick.ID, *image, *diskGB, fullScript)
				if err != nil {
					fmt.Printf("  ❌ Offer %d unavailable: %v\n", pick.ID, err)
					continue
				}
				inst = inst2
				fmt.Printf("  ✅ Launched Contract ID: %d — waiting for boot (timeout: %s)...\n", inst.ID, bootTimeout)

				// Poll with boot timeout
				deadline := time.Now().Add(bootTimeout)
				booted := false
				for time.Now().Before(deadline) {
					time.Sleep(10 * time.Second)
					status, err := client.GetInstance(inst.ID)
					if err != nil {
						fmt.Printf(".")
						continue
					}
					if status.Status == "running" && status.SshHost != "" {
						sshHost = status.SshHost
						sshPort = status.SshPort
						booted = true
						break
					}
					remaining := time.Until(deadline).Round(time.Second)
					fmt.Printf("  [%s] status=%s (%s remaining)\n", time.Now().Format("15:04:05"), status.Status, remaining)
				}

				if booted {
					fmt.Printf("\n✅ Instance is RUNNING!\n")
					fmt.Printf("SSH: ssh -p %d root@%s -L 8188:localhost:8188\n", sshPort, sshHost)
					break
				}

				// Boot timeout — destroy and try next
				fmt.Printf("\n⚠️  Instance %d stuck (host %d) — destroying and trying next offer...\n", inst.ID, pick.HostID)
				client.DestroyInstance(inst.ID)
				inst = nil
			}
			if inst == nil {
				log.Fatalf("All %d offers failed to boot within %s timeout", maxTries, bootTimeout)
			}

			if *tunnel {
				fmt.Println("\nEstablishing SSH tunnel (L:8188 -> R:8188) and streaming logs...")

				var sshClient *ssh.Client
				var err error
				// Retry connection for up to 60s as sshd might be starting
				for i := 0; i < 12; i++ {
					sshClient, err = ssh.Connect(sshHost, sshPort, "root")
					if err == nil {
						break
					}
					time.Sleep(5 * time.Second)
					fmt.Printf("Waiting for SSH... (%d/12)\n", i+1)
				}
				if err != nil {
					log.Fatalf("SSH connect failed after retries: %v. Ensure your key is added to Vast and ~/.ssh/id_rsa exists.", err)
				}
				defer sshClient.Close()

				// Forward ComfyUI
				if err := sshClient.Forward(8188, 8188); err != nil {
					log.Printf("Warning: Port forwarding failed: %v", err)
				} else {
					fmt.Println("Tunnel Active: http://localhost:8188")
				}

				// Stream logs
				go func() {
					fmt.Println("--- REMOTE LOGS (/tmp/provision.log) ---")
					sshClient.Run("tail -f /tmp/provision.log", os.Stdout, os.Stderr)
				}()

				// Wait for interrupt
				c := make(chan os.Signal, 1)
				signal.Notify(c, os.Interrupt)
				<-c
				fmt.Println("\nStopping tunnel...")
			}
		}

	case "list":
		{
			instances, err := client.ListInstances()
			if err != nil {
				log.Fatalf("List failed: %v", err)
			}
			fmt.Printf("Active Instances: %d\n", len(instances))
			for i, inst := range instances {
				fmt.Printf("[%d] ID: %d | Status: %s | SSH: %s:%d\n",
					i+1, inst.ID, inst.Status, inst.SshHost, inst.SshPort)
			}
		}

	case "destroy":
		{
			idStr := flag.Arg(1)
			if idStr == "" {
				log.Fatal("Instance ID required (vastctl destroy <ID>)")
			}
			id, err := strconv.Atoi(idStr)
			if err != nil {
				log.Fatalf("Invalid ID %s: %v", idStr, err)
			}

			fmt.Printf("Destroying instance %d...\n", id)
			if err := client.DestroyInstance(id); err != nil {
				log.Fatalf("Destroy failed: %v", err)
			}
			fmt.Println("Instance destroyed successfully.")
		}

	default:
		fmt.Println("Usage: vastctl [search|launch|list|destroy]")
	}
}
