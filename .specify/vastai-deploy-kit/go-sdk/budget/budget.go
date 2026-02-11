// Package budget implements cost guardrails for compute spending.
// Tracks per-day and per-instance spending, enforces limits, and
// auto-destroys instances that exceed idle timeout or budget caps.
package budget

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"
)

// Guard enforces spending limits across all compute providers.
type Guard struct {
	mu sync.Mutex

	DailyBudget float64       // max $/day across all providers
	MaxPerHour  float64       // max $/hr for any single instance
	IdleTimeout time.Duration // destroy instance after this idle time

	// State
	dailySpend    map[string]float64 // date → total spend
	instanceSpend map[string]*InstanceTracker
	lastReset     time.Time
}

// InstanceTracker tracks spend for one running instance.
type InstanceTracker struct {
	InstanceID   string
	ProviderName string
	PricePerHour float64
	StartedAt    time.Time
	LastActivity time.Time
	TotalSpend   float64
}

// NewGuard creates a cost guard with the given limits.
func NewGuard(dailyBudget, maxPerHour float64, idleTimeout time.Duration) *Guard {
	return &Guard{
		DailyBudget:   dailyBudget,
		MaxPerHour:    maxPerHour,
		IdleTimeout:   idleTimeout,
		dailySpend:    make(map[string]float64),
		instanceSpend: make(map[string]*InstanceTracker),
		lastReset:     time.Now(),
	}
}

// CanLaunch checks if budget allows launching a new instance at the given price.
func (g *Guard) CanLaunch(pricePerHour float64) (bool, string) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if pricePerHour > g.MaxPerHour {
		return false, fmt.Sprintf("instance price $%.3f/hr exceeds max $%.2f/hr", pricePerHour, g.MaxPerHour)
	}

	today := time.Now().Format("2006-01-02")
	if g.dailySpend[today] >= g.DailyBudget {
		return false, fmt.Sprintf("daily budget exhausted ($%.2f/$%.2f)", g.dailySpend[today], g.DailyBudget)
	}

	// Project: if we add this instance for 1 hour, would we exceed budget?
	projected := g.dailySpend[today] + pricePerHour
	if projected > g.DailyBudget*1.1 { // 10% buffer
		return false, fmt.Sprintf("projected spend $%.2f would exceed daily budget $%.2f", projected, g.DailyBudget)
	}

	return true, ""
}

// TrackInstance starts tracking spend for a new instance.
func (g *Guard) TrackInstance(instanceID, providerName string, pricePerHour float64) {
	g.mu.Lock()
	defer g.mu.Unlock()

	g.instanceSpend[instanceID] = &InstanceTracker{
		InstanceID:   instanceID,
		ProviderName: providerName,
		PricePerHour: pricePerHour,
		StartedAt:    time.Now(),
		LastActivity: time.Now(),
	}

	log.Printf("[Budget] Tracking instance %s at $%.3f/hr", instanceID, pricePerHour)
}

// RecordActivity marks an instance as active (resets idle timer).
func (g *Guard) RecordActivity(instanceID string) {
	g.mu.Lock()
	defer g.mu.Unlock()

	if t, ok := g.instanceSpend[instanceID]; ok {
		t.LastActivity = time.Now()
	}
}

// RecordSpend adds a specific cost to the daily total and instance tracker.
func (g *Guard) RecordSpend(instanceID string, amount float64) {
	g.mu.Lock()
	defer g.mu.Unlock()

	today := time.Now().Format("2006-01-02")
	g.dailySpend[today] += amount

	if t, ok := g.instanceSpend[instanceID]; ok {
		t.TotalSpend += amount
		t.LastActivity = time.Now()
	}

	log.Printf("[Budget] +$%.4f (instance %s) — daily total: $%.4f/$%.2f",
		amount, instanceID, g.dailySpend[today], g.DailyBudget)
}

// StopTracking removes an instance from tracking.
func (g *Guard) StopTracking(instanceID string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.instanceSpend, instanceID)
}

// GetDailySpend returns today's total spend.
func (g *Guard) GetDailySpend() float64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	today := time.Now().Format("2006-01-02")
	return g.dailySpend[today]
}

// GetStatus returns a summary of the budget state.
func (g *Guard) GetStatus() map[string]interface{} {
	g.mu.Lock()
	defer g.mu.Unlock()

	today := time.Now().Format("2006-01-02")
	instances := make([]map[string]interface{}, 0)
	for _, t := range g.instanceSpend {
		elapsed := time.Since(t.StartedAt).Hours()
		instances = append(instances, map[string]interface{}{
			"instance_id":    t.InstanceID,
			"provider":       t.ProviderName,
			"price_per_hour": t.PricePerHour,
			"elapsed_hours":  elapsed,
			"total_spend":    t.TotalSpend,
			"idle_seconds":   time.Since(t.LastActivity).Seconds(),
		})
	}

	return map[string]interface{}{
		"daily_budget":     g.DailyBudget,
		"daily_spend":      g.dailySpend[today],
		"daily_remaining":  g.DailyBudget - g.dailySpend[today],
		"max_per_hour":     g.MaxPerHour,
		"idle_timeout_min": g.IdleTimeout.Minutes(),
		"active_instances": instances,
	}
}

// EnforceLoop runs a background loop that checks for:
// 1. Instances exceeding idle timeout → auto-destroy
// 2. Instances exceeding hourly accrual → update daily spend
// 3. Daily budget exceeded → destroy all instances
func (g *Guard) EnforceLoop(ctx context.Context, destroyFn func(instanceID, provider string) error, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			g.enforce(destroyFn)
		}
	}
}

func (g *Guard) enforce(destroyFn func(instanceID, provider string) error) {
	g.mu.Lock()
	today := time.Now().Format("2006-01-02")

	var toDestroy []InstanceTracker
	for _, t := range g.instanceSpend {
		// Accrue hourly cost
		elapsed := time.Since(t.StartedAt).Hours()
		accrued := elapsed * t.PricePerHour
		t.TotalSpend = accrued
		g.dailySpend[today] = 0
		// Recalculate daily from all instances
		for _, it := range g.instanceSpend {
			g.dailySpend[today] += it.TotalSpend
		}

		// Check idle timeout
		if g.IdleTimeout > 0 && time.Since(t.LastActivity) > g.IdleTimeout {
			log.Printf("[Budget] ⚠️ Instance %s idle for %s (timeout: %s) — DESTROYING",
				t.InstanceID, time.Since(t.LastActivity).Round(time.Second), g.IdleTimeout)
			toDestroy = append(toDestroy, *t)
			continue
		}

		// Check per-hour cap
		if t.PricePerHour > g.MaxPerHour {
			log.Printf("[Budget] ⚠️ Instance %s exceeds max $/hr ($%.3f > $%.2f) — DESTROYING",
				t.InstanceID, t.PricePerHour, g.MaxPerHour)
			toDestroy = append(toDestroy, *t)
			continue
		}
	}

	// Check daily budget
	if g.dailySpend[today] >= g.DailyBudget {
		log.Printf("[Budget] 🛑 Daily budget exhausted ($%.2f/$%.2f) — DESTROYING ALL",
			g.dailySpend[today], g.DailyBudget)
		for _, t := range g.instanceSpend {
			toDestroy = append(toDestroy, *t)
		}
	}
	g.mu.Unlock()

	// Destroy outside lock
	for _, t := range toDestroy {
		if err := destroyFn(t.InstanceID, t.ProviderName); err != nil {
			log.Printf("[Budget] Failed to destroy %s: %v", t.InstanceID, err)
		} else {
			log.Printf("[Budget] ✅ Destroyed instance %s (saved $%.4f/hr)", t.InstanceID, t.PricePerHour)
			g.StopTracking(t.InstanceID)
		}
	}
}
