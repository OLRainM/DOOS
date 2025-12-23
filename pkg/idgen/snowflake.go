package idgen

import (
	"errors"
	"sync"
	"time"
)

const (
	// 时间戳占用位数
	timestampBits = 41
	// 机器ID占用位数
	machineIDBits = 10
	// 序列号占用位数
	sequenceBits = 12

	// 最大机器ID
	maxMachineID = -1 ^ (-1 << machineIDBits)
	// 最大序列号
	maxSequence = -1 ^ (-1 << sequenceBits)

	// 时间戳左移位数
	timestampShift = machineIDBits + sequenceBits
	// 机器ID左移位数
	machineIDShift = sequenceBits

	// 起始时间戳 (2024-01-01 00:00:00 UTC)
	epoch = 1704067200000
)

// SnowflakeGenerator Snowflake ID生成器
type SnowflakeGenerator struct {
	mu          sync.Mutex
	machineID   int64
	sequence    int64
	lastTimestamp int64
}

// NewSnowflakeGenerator 创建新的Snowflake生成器
func NewSnowflakeGenerator(machineID int64) (*SnowflakeGenerator, error) {
	if machineID < 0 || machineID > maxMachineID {
		return nil, errors.New("machine ID must be between 0 and 1023")
	}

	return &SnowflakeGenerator{
		machineID: machineID,
		sequence:  0,
		lastTimestamp: 0,
	}, nil
}

// NextID 生成下一个ID
func (s *SnowflakeGenerator) NextID() (int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	timestamp := s.currentTimestamp()

	if timestamp < s.lastTimestamp {
		return 0, errors.New("clock moved backwards")
	}

	if timestamp == s.lastTimestamp {
		s.sequence = (s.sequence + 1) & maxSequence
		if s.sequence == 0 {
			// 序列号用完，等待下一毫秒
			timestamp = s.waitNextMillis(timestamp)
		}
	} else {
		s.sequence = 0
	}

	s.lastTimestamp = timestamp

	id := ((timestamp - epoch) << timestampShift) |
		(s.machineID << machineIDShift) |
		s.sequence

	return id, nil
}

// currentTimestamp 获取当前时间戳（毫秒）
func (s *SnowflakeGenerator) currentTimestamp() int64 {
	return time.Now().UnixNano() / 1e6
}

// waitNextMillis 等待下一毫秒
func (s *SnowflakeGenerator) waitNextMillis(timestamp int64) int64 {
	for timestamp <= s.lastTimestamp {
		timestamp = s.currentTimestamp()
	}
	return timestamp
}
