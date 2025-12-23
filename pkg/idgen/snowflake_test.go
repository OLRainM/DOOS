package idgen

import (
	"sync"
	"testing"
)

func TestSnowflakeGenerator_NextID(t *testing.T) {
	gen, err := NewSnowflakeGenerator(1)
	if err != nil {
		t.Fatalf("Failed to create generator: %v", err)
	}

	id1, err := gen.NextID()
	if err != nil {
		t.Fatalf("Failed to generate ID: %v", err)
	}

	id2, err := gen.NextID()
	if err != nil {
		t.Fatalf("Failed to generate ID: %v", err)
	}

	if id1 >= id2 {
		t.Errorf("IDs should be increasing: %d >= %d", id1, id2)
	}
}

func TestSnowflakeGenerator_Concurrent(t *testing.T) {
	gen, _ := NewSnowflakeGenerator(1)
	
	const goroutines = 100
	const idsPerGoroutine = 100
	
	ids := make(map[int64]bool)
	var mu sync.Mutex
	var wg sync.WaitGroup
	
	wg.Add(goroutines)
	for i := 0; i < goroutines; i++ {
		go func() {
			defer wg.Done()
			for j := 0; j < idsPerGoroutine; j++ {
				id, err := gen.NextID()
				if err != nil {
					t.Errorf("Failed to generate ID: %v", err)
					return
				}
				
				mu.Lock()
				if ids[id] {
					t.Errorf("Duplicate ID generated: %d", id)
				}
				ids[id] = true
				mu.Unlock()
			}
		}()
	}
	
	wg.Wait()
	
	expectedCount := goroutines * idsPerGoroutine
	if len(ids) != expectedCount {
		t.Errorf("Expected %d unique IDs, got %d", expectedCount, len(ids))
	}
}

func TestSnowflakeGenerator_InvalidMachineID(t *testing.T) {
	_, err := NewSnowflakeGenerator(-1)
	if err == nil {
		t.Error("Expected error for negative machine ID")
	}

	_, err = NewSnowflakeGenerator(1024)
	if err == nil {
		t.Error("Expected error for machine ID > 1023")
	}
}
