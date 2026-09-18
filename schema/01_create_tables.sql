-- =============================================================================
-- E-commerce Analytics: Schema
-- Database: PostgreSQL 14+
-- =============================================================================
-- Star-ish schema centered on order_items (the grain at which revenue is
-- recognized). Dimensions: customers, products, categories, campaigns.
-- =============================================================================

DROP SCHEMA IF EXISTS shop CASCADE; --If an old Shoplytics database exists, delete it and everything inside it.
CREATE SCHEMA shop;
SET search_path TO shop, public; --When I say customers, look inside shop first

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
-- Products(this query is about What are we selling?)
-- -----------------------------------------------------------------------------
CREATE TABLE products (
    product_id   SERIAL PRIMARY KEY,
    sku          TEXT        NOT NULL UNIQUE,
    name         TEXT        NOT NULL,
    category_id  INTEGER     NOT NULL REFERENCES categories(category_id),
    cost         NUMERIC(10,2) NOT NULL CHECK (cost  >= 0), --cost cannot be negative
    list_price   NUMERIC(10,2) NOT NULL CHECK (list_price >= 0),
    launch_date  DATE        NOT NULL,
    is_active    BOOLEAN     NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- Customers(query about Who is shopping?)
-- -----------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id  SERIAL PRIMARY KEY,
    email        TEXT        NOT NULL UNIQUE,
    first_name   TEXT        NOT NULL,
    last_name    TEXT        NOT NULL,
    signup_date  DATE        NOT NULL, --for cohort analysis(customer who joined this particular time how well did they retain)
    country      TEXT        NOT NULL,
    city         TEXT        NOT NULL,
    birth_year   INTEGER     CHECK (birth_year BETWEEN 1920 AND 2015)
);

-- -----------------------------------------------------------------------------
-- Marketing campaigns (How did we acquire customers?)(via campaigns ex:- diwali ads) 
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

-- which campaign brought the customer in?
--first-touch attribution(saw google ad->read an email on that pdt->purchased that pdt. So google ad gets all credit for the sale as it introduced(first touch)
CREATE TABLE customer_acquisition (
    customer_id  INTEGER PRIMARY KEY REFERENCES customers(customer_id),
    campaign_id  INTEGER REFERENCES campaigns(campaign_id)
);

-- -----------------------------------------------------------------------------
-- Orders (header) and order_items (lines)
-- What orders did customers place?
-- -----------------------------------------------------------------------------
-- revenue is recognised in this table cuz :- orders-\>order_items->revenue->analytics
CREATE TABLE orders (
    order_id        BIGSERIAL PRIMARY KEY,
    customer_id     INTEGER     NOT NULL REFERENCES customers(customer_id), -- Customer : Orders = 1 to Many(since customer can place many orders)
    order_date      TIMESTAMPTZ NOT NULL,
    status          TEXT        NOT NULL CHECK (status IN ('placed','shipped','delivered','cancelled')),
    payment_method  TEXT        NOT NULL CHECK (payment_method IN ('card','paypal','apple_pay','gift_card'))
);

CREATE TABLE order_items (
    order_item_id   BIGSERIAL PRIMARY KEY,
    order_id        BIGINT      NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE, --if an order is deleted the order_item is deleted too
    product_id      INTEGER     NOT NULL REFERENCES products(product_id),
    quantity        INTEGER     NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_pct    NUMERIC(4,2) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 100)
);

-- -----------------------------------------------------------------------------
-- Returns (Was this order item returned?)
-- -----------------------------------------------------------------------------
CREATE TABLE returns (
    return_id      BIGSERIAL PRIMARY KEY,
    order_item_id  BIGINT      NOT NULL UNIQUE REFERENCES order_items(order_item_id) ON DELETE CASCADE,
    return_date    TIMESTAMPTZ NOT NULL,
    reason         TEXT        NOT NULL CHECK (reason IN ('defective','wrong_item','no_longer_wanted','damaged_shipping','other'))
);
