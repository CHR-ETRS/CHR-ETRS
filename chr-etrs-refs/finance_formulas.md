# Exact formulas from chr_financial_simulator.py

Defaults: N=500, avg_monthly=25000, revenue=300e6, non_payroll_opex=105e6,
baseline_turnover=0.22, baseline_deprivation_pct=0.20

payroll = N * avg_monthly * 12
daily_wage = (avg_monthly*12) / 264
turnover_cost_per = 20000 + 85000  # 105000

## Nominal P&L
ebitda_nominal = revenue - (payroll + non_payroll_opex)  # = 45e6, margin 15%

## Shadow costs
num_deprived = int(N * deprivation_pct)
deprivation_tax = num_deprived * (avg_monthly*12) * 0.12
num_departures = int(N * turnover_rate)
emotional_debt = num_departures * 105000
burnout_liability = num_deprived * (1.25*12) * daily_wage
shadow_total = deprivation_tax + emotional_debt + burnout_liability

## Pre-CHR real EBITDA
real_pre = ebitda_nominal - shadow_total  # ~28,145,455

## Post CHR-OS
post_deprivation_pct = 0.0
post_turnover = baseline_turnover * 0.50
post_burnout_pct = baseline_deprivation_pct * 0.20
# recalculate shadow with those; burnout uses num_burned = int(N*post_burnout_pct) * 15 * daily_wage
# real_post = ebitda_nominal - post_shadow - 350000
# ROI = (savings - capex)/capex*100; ROV = savings/capex
# At defaults: shadow 16,854,545; after EBITDA 38,534,091; ROI ~2968%; ROV 30.68x

## Diluted wage
nominal_hr = avg_monthly / (40*4.33)  # 144.34
diluted_hr = avg_monthly / (55*4.33)  # 104.98
erosion = (nominal_hr-diluted_hr)/nominal_hr*100  # 27.27%
