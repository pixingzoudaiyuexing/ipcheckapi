package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestHealth(t *testing.T) {
	a := &app{apiKey: "secret", probeName: "cn", timeout: time.Second}
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rr := httptest.NewRecorder()
	a.health(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rr.Code, rr.Body.String())
	}
	if !strings.Contains(rr.Body.String(), `"probe":"cn"`) {
		t.Fatalf("unexpected body: %s", rr.Body.String())
	}
}

func TestCheckRequiresAPIKey(t *testing.T) {
	a := &app{apiKey: "secret", probeName: "cn", timeout: time.Second}
	req := httptest.NewRequest(http.MethodGet, "/check?ip=127.0.0.1&port=80", nil)
	rr := httptest.NewRecorder()
	a.check(rr, req)
	if rr.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d body=%s", rr.Code, rr.Body.String())
	}
}

func TestCheckRejectsInvalidInput(t *testing.T) {
	a := &app{apiKey: "secret", probeName: "cn", timeout: time.Second}
	req := httptest.NewRequest(http.MethodGet, "/check?ip=example.com&port=70000", nil)
	req.Header.Set("X-API-Key", "secret")
	rr := httptest.NewRecorder()
	a.check(rr, req)
	if rr.Code != http.StatusBadRequest {
		t.Fatalf("status=%d body=%s", rr.Code, rr.Body.String())
	}
}
