package ssh

import (
	"fmt"
	"io"
	"net"
	"os"
	"os/user"
	"path/filepath"
	"time"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
)

type Client struct {
	Client *ssh.Client
}

func Connect(host string, port int, username string) (*Client, error) {
	// Try agent first
	var signers []ssh.Signer
	if sock := os.Getenv("SSH_AUTH_SOCK"); sock != "" {
		if conn, err := net.Dial("unix", sock); err == nil {
			agentClient := agent.NewClient(conn)
			s, err := agentClient.Signers()
			if err == nil {
				signers = append(signers, s...)
			}
		}
	}

	// Try ~/.ssh/id_rsa if exists
	usr, _ := user.Current()
	keyPath := filepath.Join(usr.HomeDir, ".ssh", "id_rsa")
	if _, err := os.Stat(keyPath); err == nil {
		key, err := os.ReadFile(keyPath)
		if err == nil {
			signer, err := ssh.ParsePrivateKey(key)
			if err == nil {
				signers = append(signers, signer)
			}
		}
	}

	if len(signers) == 0 {
		return nil, fmt.Errorf("no ssh keys found (agent or ~/.ssh/id_rsa)")
	}

	config := &ssh.ClientConfig{
		User: username,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(signers...),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(), // Vast hosts change often
		Timeout:         10 * time.Second,
	}

	addr := fmt.Sprintf("%s:%d", host, port)
	client, err := ssh.Dial("tcp", addr, config)
	if err != nil {
		return nil, fmt.Errorf("dial failed: %w", err)
	}

	return &Client{
		Client: client,
	}, nil
}

func (c *Client) Run(cmd string, out io.Writer, errOut io.Writer) error {
	session, err := c.Client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	if out != nil {
		session.Stdout = out
	}
	if errOut != nil {
		session.Stderr = errOut
	}

	return session.Run(cmd)
}

func (c *Client) Forward(localPort, remotePort int) error {
	localListener, err := net.Listen("tcp", fmt.Sprintf("localhost:%d", localPort))
	if err != nil {
		return fmt.Errorf("local listen failed: %w", err)
	}

	go func() {
		for {
			localConn, err := localListener.Accept()
			if err != nil {
				return
			}
			go c.handleForward(localConn, remotePort)
		}
	}()

	return nil
}

func (c *Client) handleForward(localConn net.Conn, remotePort int) {
	defer localConn.Close()

	remoteConn, err := c.Client.Dial("tcp", fmt.Sprintf("localhost:%d", remotePort))
	if err != nil {
		// Only log on verbose?
		return
	}
	defer remoteConn.Close()

	go io.Copy(localConn, remoteConn)
	io.Copy(remoteConn, localConn)
}

func (c *Client) Close() {
	if c.Client != nil {
		c.Client.Close()
	}
}
