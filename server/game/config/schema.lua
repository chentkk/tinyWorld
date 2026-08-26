-- game/config/schema.lua
-- 最简 mysql 建表 SQL(同时提供给 db 工具创建表)。
-- mock 模式下用 mocks 初始化测试数据。

return {
    sql = {
        [[CREATE TABLE IF NOT EXISTS accounts (
            id INT PRIMARY KEY AUTO_INCREMENT,
            name VARCHAR(64) UNIQUE NOT NULL,
            password VARCHAR(128) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )]],
        [[CREATE TABLE IF NOT EXISTS players (
            id INT PRIMARY KEY AUTO_INCREMENT,
            account_id INT NOT NULL,
            name VARCHAR(64) NOT NULL,
            level INT DEFAULT 1,
            hp INT DEFAULT 100, max_hp INT DEFAULT 100,
            mp INT DEFAULT 100, max_mp INT DEFAULT 100,
            gold INT DEFAULT 0,
            scene VARCHAR(64) DEFAULT 'main',
            x DOUBLE DEFAULT 10.0, y DOUBLE DEFAULT 10.0,
            INDEX idx_account (account_id)
        )]],
        [[CREATE TABLE IF NOT EXISTS player_bin (
            player_id INT PRIMARY KEY,
            bin MEDIUMBLOB,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )]],
    },
    mocks = {
        "CREATE TABLE accounts",
        "INSERT INTO accounts (id,name,password) VALUES (1,'test1','123456')",
        "CREATE TABLE players",
        "INSERT INTO players (id,account_id,name,level,hp,max_hp,mp,max_mp,gold,scene,x,y) VALUES (1,1,'test1',1,100,100,100,100,0,'main',10.0,10.0)",
        "CREATE TABLE player_bin",
    },
}
