package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

var version = "dev"

type app struct {
	apiKey    string
	probeName string
	timeout   time.Duration
}

type tcpResult struct {
	Reachable bool   `json:"reachable"`
	Status    string `json:"status"`
	LatencyMS int64  `json:"latency_ms"`
}

type checkResponse struct {
	Success bool      `json:"success"`
	Probe   string    `json:"probe"`
	Target  string    `json:"target"`
	Port    int       `json:"port"`
	TCP     tcpResult `json:"tcp"`
}

type errorResponse struct {
	Success bool   `json:"success"`
	Error   string `json:"error"`
}

func main() {
	listenAddr := envOr("LISTEN_ADDR", "0.0.0.0:18080")
	probeName := envOr("PROBE_NAME", "probe")
	apiKey := strings.TrimSpace(os.Getenv("API_KEY"))
	if apiKey == "" {
		log.Fatal("API_KEY is required")
	}

	timeout := 5 * time.Second
	if raw := strings.TrimSpace(os.Getenv("CHECK_TIMEOUT")); raw != "" {
		parsed, err := time.ParseDuration(raw)
		if err != nil || parsed <= 0 || parsed > 30*time.Second {
			log.Fatalf("invalid CHECK_TIMEOUT %q (allowed: >0 and <=30s)", raw)
		}
		timeout = parsed
	}

	a := &app{apiKey: apiKey, probeName: probeName, timeout: timeout}
	mux := http.NewServeMux()
	mux.HandleFunc("/health", a.health)
	mux.HandleFunc("/check", a.check)

	server := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      35 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	log.Printf("ipcheckapi %s listening on %s (probe=%s timeout=%s)", version, listenAddr, probeName, timeout)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func (a *app) health(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"probe":   a.probeName,
		"version": version,
	})
}

func (a *app) check(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	if !validAPIKey(r.Header.Get("X-API-Key"), a.apiKey) {
		writeJSON(w, http.StatusUnauthorized, errorResponse{Success: false, Error: "unauthorized"})
		return
	}

	ipText := strings.TrimSpace(r.URL.Query().Get("ip"))
	ip := net.ParseIP(ipText)
	if ip == nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Success: false, Error: "invalid_ip"})
		return
	}

	port, err := strconv.Atoi(r.URL.Query().Get("port"))
	if err != nil || port < 1 || port > 65535 {
		writeJSON(w, http.StatusBadRequest, errorResponse{Success: false, Error: "invalid_port"})
		return
	}

	target := net.JoinHostPort(ip.String(), strconv.Itoa(port))
	started := time.Now()
	conn, err := net.DialTimeout("tcp", target, a.timeout)
	latency := time.Since(started).Milliseconds()

	result := tcpResult{Reachable: false, Status: "error", LatencyMS: latency}
	if err == nil {
		result.Reachable = true
		result.Status = "open"
		_ = conn.Close()
	} else if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
		result.Status = "timeout"
	} else if isConnectionRefused(err) {
		result.Status = "closed"
	}

	writeJSON(w, http.StatusOK, checkResponse{
		Success: true,
		Probe:   a.probeName,
		Target:  ip.String(),
		Port:    port,
		TCP:     result,
	})
}

func validAPIKey(got, expected string) bool {
	got = strings.TrimSpace(got)
	if got == "" || expected == "" || len(got) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(expected)) == 1
}

func isConnectionRefused(err error) bool {
	if err == nil {
		return false
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "connection refused")
}

func methodNotAllowed(w http.ResponseWriter) {
	w.Header().Set("Allow", http.MethodGet)
	writeJSON(w, http.StatusMethodNotAllowed, errorResponse{Success: false, Error: "method_not_allowed"})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("write json: %v", err)
	}
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}
