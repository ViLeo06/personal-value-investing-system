-- Gate-0 model-family routing. Idempotent for current open assignment.

insert into model.issuer_model_assignments (issuer_id,model_family,valid_from,rationale)
select issuer_id,'owner_earnings_dcf','2001-08-27','High-moat consumer; Owner Earnings DCF with DDM/relative/Reverse DCF cross-checks.'
from master.issuers i where issuer_code='KWEICHOW_MOUTAI'
and not exists (select 1 from model.issuer_model_assignments a where a.issuer_id=i.issuer_id and a.valid_to is null);

insert into model.issuer_model_assignments (issuer_id,model_family,valid_from,rationale)
select issuer_id,'fcff_sotp','2004-06-16','Platform technology; FCFF/DCF plus SOTP and Reverse DCF.'
from master.issuers i where issuer_code='TENCENT'
and not exists (select 1 from model.issuer_model_assignments a where a.issuer_id=i.issuer_id and a.valid_to is null);

insert into model.issuer_model_assignments (issuer_id,model_family,valid_from,rationale)
select issuer_id,'value_driver_fcff','2002-07-31','Capital-intensive manufacturing growth; FCFF with ROIC/RONIC and normalized earnings.'
from master.issuers i where issuer_code='BYD'
and not exists (select 1 from model.issuer_model_assignments a where a.issuer_id=i.issuer_id and a.valid_to is null);

insert into model.issuer_model_assignments (issuer_id,model_family,valid_from,rationale)
select issuer_id,'residual_income','2002-04-09','Bank; residual income with P/B, DDM and reverse-implied ROE.'
from master.issuers i where issuer_code='CMB'
and not exists (select 1 from model.issuer_model_assignments a where a.issuer_id=i.issuer_id and a.valid_to is null);
