-- =============================================================================
-- E-commerce Analytics: Schema
-- Database: PostgreSQL 14+
-- =============================================================================
-- Star-ish schema centered on order_items (the grain at which revenue is
-- recognized). Dimensions: customers, products, categories, campaigns.
-- =============================================================================

DROP SCHEMA IF EXISTS shop CASCADE;
CREATE SCHEMA shop;
SET search_path TO shop, public;

-- -----------------------------------------------------------------------------
-- Categories (self-referential hierarchy: Electronics > Computers > Laptops)
-- -----------------------------------------------------------------------------
CREATE TABLE categories (
    category_id        SERIAL PRIMARY KEY,
    name               TEXT        NOT NULL,
    parent_category_id INTEGER REFERENCES categories(category_id),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- Products
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    sku          TEXT        NOT NULL UNIQUE,
    name         TEXT        NOT NULL,
    category_id  INTEGER     NOT NULL REFERENCES categories(category_id),
    cost         NUMERIC(10,2) NOT NULL CHECK (cost  >= 0),
    list_price   NUMERIC(10,2) NOT NULL CHECK (list_price >= 0),
    launch_date  DATE        NOT NULL,
    is_active    BOOLEAN     NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- Customers
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    email        TEXT        NOT NULL UNIQUE,
    first_name   TEXT        NOT NULL,
    last_name    TEXT        NOT NULL,
    signup_date  DATE        NOT NULL,
    country      TEXT        NOT NULL,
    city         TEXT        NOT NULL,
    birth_year   INTEGER     CHECK (birth_year BETWEEN 1920 AND 2015)
);

-- -----------------------------------------------------------------------------
-- Marketing campaigns (for attribution / cohort analysis)
-- -----------------------------------------------------------------------------
CREATE TABLE campaigns (
    campaign_id  SERIAL PRIMARY KEY,
    name         TEXT        NOT NULL,
    channel      TEXT        NOT NULL CHECK (channel IN ('email','paid_search','social','display','referral','organic')),
    start_date   DATE        NOT NULL,
    end_date     DATE        NOT NULL,
    spend_usd    NUMERIC(12,2) NOT NULL CHECK (spend_usd >= 0),
    CHECK (end_date >= start_date)
);

-- First-touch attribution: which campaign brought the customer in?
CREATE TABLE customer_acquisition (
    customer_id  INTEGER PRIMARY KEY REFERENCES customers(customer_id),
    campaign_id  INTEGER REFERENCES campaigns(campaign_id)
);

-- -----------------------------------------------------------------------------
-- Orders (header) and order_items (lines)
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id        BIGSERIAL PRIMARY KEY,
    customer_id     INTEGER     NOT NULL REFERENCES customers(customer_id),
    order_date      TIMESTAMPTZ NOT NULL,
    status          TEXT        NOT NULL CHECK (status IN ('placed','shipped','delivered','cancelled')),
    payment_method  TEXT        NOT NULL CHECK (payment_method IN ('card','paypal','apple_pay','gift_card'))
);

CREATE TABLE order_items (
    order_item_id   BIGSERIAL PRIMARY KEY,
    order_id        BIGINT      NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id      INTEGER     NOT NULL REFERENCES products(product_id),
    quantity        INTEGER     NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_pct    NUMERIC(4,2) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 100)
);

-- -----------------------------------------------------------------------------
-- Returns (one row per returned order_item; partial returns aren't modeled)
-- -----------------------------------------------------------------------------
CREATE TABLE returns (
    return_id      BIGSERIAL PRIMARY KEY,
    order_item_id  BIGINT      NOT NULL UNIQUE REFERENCES order_items(order_item_id) ON DELETE CASCADE,
    return_date    TIMESTAMPTZ NOT NULL,
    reason         TEXT        NOT NULL CHECK (reason IN ('defective','wrong_item','no_longer_wanted','damaged_shipping','other'))
);
