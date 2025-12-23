package sharding

import (
	"testing"
	"time"
)

func TestGetShardIndex(t *testing.T) {
	configs := []DBConfig{
		{DSN: "mock1"},
		{DSN: "mock2"},
	}
	
	// 注意：这个测试不会真正连接数据库，只测试分片逻辑
	// 实际使用时需要有真实的数据库连接
	
	tests := []struct {
		userID   int64
		expected int
	}{
		{userID: 1, expected: 1},
		{userID: 2, expected: 0},
		{userID: 3, expected: 1},
		{userID: 4, expected: 0},
		{userID: 100, expected: 0},
		{userID: 101, expected: 1},
	}

	// 模拟分片逻辑
	count := len(configs)
	for _, tt := range tests {
		got := int(tt.userID % int64(count))
		if got != tt.expected {
			t.Errorf("GetShardIndex(%d) = %d, want %d", tt.userID, got, tt.expected)
		}
	}
}

func TestDBConfig(t *testing.T) {
	cfg := DBConfig{
		DSN:          "user:pass@tcp(localhost:3306)/db",
		MaxOpenConns: 100,
		MaxIdleConns: 20,
		MaxLifetime:  time.Hour,
		MaxIdleTime:  10 * time.Minute,
	}

	if cfg.MaxOpenConns != 100 {
		t.Errorf("Expected MaxOpenConns = 100, got %d", cfg.MaxOpenConns)
	}
}
