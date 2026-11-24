-- fetch_window(): the months loaded, for the date range and as the cache key
-- (spec section 5.2). One row; NULLs and months = 0 before the first load.
SELECT first_month, last_month, months, loaded_at
FROM app.v_window;
