-- ---------------------------------------------------------------------------
-- Benilde ClassRecord — initial schema (MariaDB / XAMPP)
--
-- The API creates this table on its own, so running this by hand is optional.
-- It is here so the schema can be read, shown in the capstone documentation,
-- or restored in phpMyAdmin without starting the API.
--
-- phpMyAdmin: select the SQL tab, paste this in, and press Go.
-- ---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS `benilde_classrecord`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

USE `benilde_classrecord`;

CREATE TABLE IF NOT EXISTS `teachers` (
    `Id`           INT           NOT NULL AUTO_INCREMENT,
    `Email`        VARCHAR(160)  NOT NULL,
    `PasswordHash` VARCHAR(255)  NOT NULL,
    `FullName`     VARCHAR(120)  NOT NULL,
    `Department`   VARCHAR(120)  NULL,
    `IsActive`     TINYINT(1)    NOT NULL DEFAULT 1,
    `CreatedAt`    DATETIME(6)   NOT NULL,
    `LastLoginAt`  DATETIME(6)   NULL,
    PRIMARY KEY (`Id`),
    UNIQUE KEY `IX_teachers_Email` (`Email`)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci;

-- Demo account: teacher@benilde.edu.ph / Benilde2026
-- The value below is a BCrypt hash. The plain password is never stored.
-- The API seeds this row by itself when the table is empty, so this insert is
-- only needed if the table is being set up by hand.
INSERT INTO `teachers`
    (`Email`, `PasswordHash`, `FullName`, `Department`, `IsActive`, `CreatedAt`)
SELECT
    'teacher@benilde.edu.ph',
    '$2a$11$WW/8E2.uDwd430v2tAIIi.gSIlLc44DIwnUMZ9/S0Ts4Ex/BNcSUi',
    'Demo Teacher',
    'Information Technology',
    1,
    UTC_TIMESTAMP(6)
WHERE NOT EXISTS (
    SELECT 1 FROM `teachers` WHERE `Email` = 'teacher@benilde.edu.ph'
);
