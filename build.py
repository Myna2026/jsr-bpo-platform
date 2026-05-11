import json, re
funcs = json.load(open('/home/claude/extracted_funcs.json'))
sst = funcs['SystemSettingsTab']

# Full balance audit
sections = list(re.finditer(r"activeSection==='(\w+)'&&\(", sst))
all_ok = True
for j, sec in enumerate(sections):
    name = sec.group(1)
    s = sec.start()
    e = sections[j+1].start() if j+1 < len(sections) else s+15000
    seg = sst[s:e]
    o = seg.count('<div')+seg.count('<span')
    c = seg.count('</div>')+seg.count('</span>')
    if o-c != 0:
        print(f"FAIL {name}: {o-c}")
        all_ok = False
if all_ok:
    print("All 20 sections balanced")

data_clean=re.sub(r'const\s*\{[^}]*useState[^}]*\}\s*=\s*React;?\s*\n','',open('/home/claude/extracted_data.txt').read())
css=open('/home/claude/extracted_css.txt').read()
groups=[('GDOCSYNC',['GoogleDocSync']),('VACATION',['VacationEngine']),('PERFORMANCE',['PerformanceEngine','PerformanceCard','PerformanceView']),('MODALS',['AbsenceModal','BonusModal','ReferralModal','QualityModal','CommModal','TerminateModal']),('EMPLOYEES',['EmployeeModal','EmployeeList']),('TRAINING',['TrainingPlanModal','TrainingPlans','Timeline']),('PAYSLIP',['calcAlbanianPayroll','PayslipEngine','PayslipPreviewModal','PayslipArchiveView']),('VIEWS',['ProductivityView','Cockpit','OrgChart','PayrollView','WorkforcePlanningView']),('FORECAST',['ForecastView']),('TESTS',['TestEditor','LanguageTestPage']),('CVS',['AudioRecorder','ContractSection','CVModal','CVResultsModal','CVsView','CandidateShowcase']),('LEARNING',['KnowledgeBase','ELearning']),('OTHER',['RecruitingKanban','OnboardingView','SkillMatrix','TimeTracking']),('PROJECTS',['ProjectDashboard','ProjectProfitability']),('ABSENCE',['AbsenceOverview']),('LOCATIONS',['LocEditModal','LocationsView']),('SPACES',['SpacesView']),('INVOICE',['InvoiceView']),('ADMIN',['RoleEditModal','ClientEditModal','ClientAccountsTab','SystemSettingsTab','ProjectsAdminTab','SuperAdminView']),('LOGIN',['LoginScreen']),('APP',['App'])]
parts=['<!DOCTYPE html><html lang="de"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no"><title>JSR BPO Intelligence Platform</title><script src="https://unpkg.com/react@18/umd/react.development.js"></script><script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script><script src="https://unpkg.com/@babel/standalone/babel.min.js"></script><script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script><style>',css,'</style></head><body><div id="root"></div><script type="text/babel">const { useState, useEffect, useRef, useMemo, useCallback } = React;',data_clean,'const CV_STATUS = STATUS_FLOW;</script>']
for label,members in groups:
    code='\n\n'.join(funcs[m] for m in members if m in funcs)
    parts.append('<script type="text/babel">'+code+'</script>')
parts.append('</body></html>')
html=''.join(parts)
html=html.replace('cv.test_answers[','(cv.test_answers||{})[')

# Scan for function decls in JSX IIFEs
iife_ok = True
for m in re.finditer(r'<script type="text/babel">', html):
    end = html.find('</script>', m.end())
    block = html[m.end():end]
    for im in re.finditer(r'\(+\(\)=>\{', block):
        chunk = block[im.start():im.start()+500]
        if 'function ' not in chunk: continue
        pre = block[max(0,im.start()-60):im.start()]
        if 'useEffect' in pre or 'useState' in pre: continue
        if '{' in pre[-10:] or 'return' in pre[-30:] or '&&(' in pre[-30:]:
            ln = block[:im.start()].count('\n')+1
            print(f"IIFE ISSUE: {re.findall(r'function (\w+)', chunk[:200])}")
            iife_ok = False
if iife_ok:
    print("No IIFE issues")

with open('/mnt/user-data/outputs/hr.html','w') as f: f.write(html)
print(f'Built: {html.count(chr(10))} lines')
