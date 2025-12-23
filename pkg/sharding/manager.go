package sharding

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/gocraft/dbr/v2"
)

// DBConfig 数据库配置
type DBConfig struct {
	DSN          string
	MaxOpenConns int
	MaxIdleConns int
	MaxLifetime  time.Duration
	MaxIdleTime  time.Duration
}

// ShardingManager 分库管理器
type ShardingManager struct {
	nodes map[int]*dbr.Connection
	count int
}

// NewShardingManager 创建分库管理器
func NewShardingManager(configs []DBConfig) (*ShardingManager, error) {
	if len(configs) == 0 {
		return nil, fmt.Errorf("at least one database config is required")
	}

	nodes := make(map[int]*dbr.Connection)
	
	for i, cfg := range configs {
		conn, err := dbr.Open("mysql", cfg.DSN, nil)
		if err != nil {
			return nil, fmt.Errorf("failed to open database %d: %w", i, err)
		}

		// 配置连接池
		db := conn.DB
		db.SetMaxOpenConns(cfg.MaxOpenConns)
		db.SetMaxIdleConns(cfg.MaxIdleConns)
		db.SetConnMaxLifetime(cfg.MaxLifetime)
		db.SetConnMaxIdleTime(cfg.MaxIdleTime)

		// 测试连接
		if err := db.Ping(); err != nil {
			return nil, fmt.Errorf("failed to ping database %d: %w", i, err)
		}

		nodes[i] = conn
	}

	return &ShardingManager{
		nodes: nodes,
		count: len(configs),
	}, nil
}

// GetSession 根据用户ID获取对应的数据库会话
func (m *ShardingManager) GetSession(userID int64) *dbr.Session {
	shardIndex := int(userID % int64(m.count))
	return m.nodes[shardIndex].NewSession(nil)
}

// GetSessionByIndex 根据索引获取数据库会话
func (m *ShardingManager) GetSessionByIndex(index int) (*dbr.Session, error) {
	if index < 0 || index >= m.count {
		return nil, fmt.Errorf("invalid shard index: %d", index)
	}
	return m.nodes[index].NewSession(nil), nil
}

// GetAllSessions 获取所有分库的会话（用于后台任务）
func (m *ShardingManager) GetAllSessions() []*dbr.Session {
	sessions := make([]*dbr.Session, 0, m.count)
	for i := 0; i < m.count; i++ {
		sessions = append(sessions, m.nodes[i].NewSession(nil))
	}
	return sessions
}

// GetShardIndex 获取用户ID对应的分库索引
func (m *ShardingManager) GetShardIndex(userID int64) int {
	return int(userID % int64(m.count))
}

// GetShardCount 获取分库数量
func (m *ShardingManager) GetShardCount() int {
	return m.count
}

// Close 关闭所有数据库连接
func (m *ShardingManager) Close() error {
	for i, conn := range m.nodes {
		if err := conn.DB.Close(); err != nil {
			return fmt.Errorf("failed to close database %d: %w", i, err)
		}
	}
	return nil
}

// HealthCheck 健康检查
func (m *ShardingManager) HealthCheck() map[int]error {
	results := make(map[int]error)
	for i, conn := range m.nodes {
		results[i] = conn.DB.Ping()
	}
	return results
}

// GetStats 获取连接池统计信息
func (m *ShardingManager) GetStats() map[int]sql.DBStats {
	stats := make(map[int]sql.DBStats)
	for i, conn := range m.nodes {
		stats[i] = conn.DB.Stats()
	}
	return stats
}
