INCLUDE PERFETTO MODULE slices.with_context;

CREATE PERFETTO VIEW lcp AS
WITH shared_sq_26 AS (
  SELECT *
  FROM slice
),
shared_sq_27 AS (
  SELECT *
  FROM shared_sq_26
  WHERE name = 'PageLoadMetrics.NavigationToLargestContentfulPaint'
),
sq_6901 AS (
  SELECT *
  FROM shared_sq_27
  ORDER BY ts DESC
  LIMIT 1
)
SELECT dur
FROM sq_6901
