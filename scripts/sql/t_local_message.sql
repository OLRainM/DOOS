CREATE TABLE IF NOT EXISTS `t_local_message` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` VARCHAR(64) NOT NULL COMMENT '消息唯一ID (UUID)',
  `tx_id` VARCHAR(64) NOT NULL COMMENT '业务事务ID (如 order_id)',
  `topic` VARCHAR(50) NOT NULL COMMENT 'MQ Topic',
  `event_type` VARCHAR(50) NOT NULL COMMENT '事件类型: order.created, stock.deduct',
  `payload` JSON NOT NULL COMMENT '消息体',
  `status` TINYINT NOT NULL DEFAULT 0 COMMENT '0-待发送, 1-已发送, 2-已确认, 3-失败',
  `retry_count` INT DEFAULT 0 COMMENT '重试次数',
  `max_retry` INT DEFAULT 5 COMMENT '最大重试次数',
  `next_retry_at` TIMESTAMP NULL COMMENT '下次重试时间',
  `error_msg` VARCHAR(500) COMMENT '失败原因',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_message_id` (`message_id`),
  KEY `idx_status_next_retry` (`status`, `next_retry_at`),
  KEY `idx_tx_id` (`tx_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='本地消息表';
