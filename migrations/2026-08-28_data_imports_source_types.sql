-- data_imports_source_type_check kannte nur rohdaten/calls/gauges/booking — der neue Quellentyp
-- calls_inbound (und booking_a/_week/_month, forecast_sales/_support, mailer) fehlte, darum scheiterte
-- Edis Inbound-Upload still an der CHECK-Constraint. Dieselbe Falle wie cvs_status_valid / calendar_events.kind.
-- Wahrheit ist UPLOAD_SOURCES in frontend/hr.html; statuscheck.js prüft ab jetzt beide gegeneinander.
alter table public.data_imports drop constraint if exists data_imports_source_type_check;
alter table public.data_imports add constraint data_imports_source_type_check
  check (source_type = any (array[
    'rohdaten','calls','calls_inbound','gauges','booking',
    'booking_a','booking_week','booking_month',
    'forecast_sales','forecast_support','longterm','mailer'
  ]::text[]));
