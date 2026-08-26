-- server/sql/init.sql
-- tinyWorld 初始建表脚本。db 工具执行本文件创建 mysql 表。
-- 至少需要: 账号表 accounts、角色表 players、玩家二进制数据表 player_bin。

CREATE DATABASE IF NOT EXISTS tinyworld DEFAULT CHARACTER SET utf8mb4;
USE tinyworld;

CREATE TABLE IF NOT EXISTS accounts (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(64) UNIQUE NOT NULL,
    password VARCHAR(128) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS players (
    id INT PRIMARY KEY AUTO_INCREMENT,
    account_id INT NOT NULL,
    name VARCHAR(64) NOT NULL,
    level INT DEFAULT 1,
    hp INT DEFAULT 100,
    max_hp INT DEFAULT 100,
    mp INT DEFAULT 100,
    max_mp INT DEFAULT 100,
    gold INT DEFAULT 0,
    scene VARCHAR(64) DEFAULT 'main',
    x DOUBLE DEFAULT 10.0,
    y DOUBLE DEFAULT 10.0,
    INDEX idx_account (account_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS player_bin (
    player_id INT PRIMARY KEY,
    bin MEDIUMBLOB,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;
