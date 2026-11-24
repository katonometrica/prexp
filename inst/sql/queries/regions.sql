-- fetch_regions(): the NHS regions, so that the Region view shows every
-- region, at 0 where a drug was not prescribed (spec section 5.2). Region '-',
-- the prescribers without a region, is not one of them.
SELECT region_code, region_name
FROM app.v_region
WHERE region_code <> '-'
ORDER BY region_code;
