CREATE TABLE IF NOT EXISTS `t_message_consume_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `message_id` VARCHAR(64) NOT NULL COMMENT '消息ID',
  `consumer_group` VARCHAR(50) NOT NULL COMMENT '消费者组',
  `status` TINYINT NOT NULL COMMENT '0-处理中, 1-成功, 2-失败',
  `retry_count` INT DEFAULT 0,
  `error_msg` VARCHAR(500),
  `consumed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_message_consumer` (`message_id`, `consumer_group`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='消息消费日志';
