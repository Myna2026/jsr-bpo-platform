-- Erste Vertragsvorlage: befristeter Arbeitsvertrag, Albanisch (Kosovo).
-- Ausgelesen aus dem Muster "Alban Selimi-1.pdf". Variable Stellen -> {{katalog_key}}
-- (CONTRACT_VARS in hr.html). Rest = fester Text (Firmenangaben, Rechtsgrundlage §03/L-212,
-- alle Klauseln Neni 1-12, Unterschrift/Stempel). body_html wird als KLARTEXT gerendert
-- (Vorschau/Druck white-space:pre-wrap), darum reiner Text mit Zeilenumbruechen.

insert into public.contract_templates (name, contract_kind, language, body_html, placeholders, active)
values (
  'Arbeitsvertrag befristet (Albanisch)',
  'befristet',
  'sq',
  $body$KONTRATË PUNE

Datë: {{date}}

Në pajtim me nenet 7, 10 par.2 pika 2.2, dhe 21 të Ligjit nr. 03/L-212, të punës i shpallur në Gazetën zyrtare të Republikës së Kosovës me datën 01.12.2010, punëdhënësi dhe punëmarrësi si subjekte të mardhënieve juridike të punës lidhin këtë

KONTRATË INDIVIDUALE PUNE
(Për kohë të caktuar):

Neni 1

Sot me datë: {{date}} lidhet kontrata e punës ndërmjet subjektit 25hours SH.P.K me seli në Prishtinë, Rr. Xhevdet Doda, Lagjia Lakrisht Obj. Dukagjini Center-2, pn, me numër unik indetifikues 812231231, përfaqësuar nga z. Kodret Zeneli në pozitën e Drejtorit (në tekstin e mëtejmë "Punëdhënësi"), dhe:

{{name}} me numër te letërnjoftimit të lëshuar në Kosovë: {{id_number}} (në tekstin e mëtejmë "Punëmarrësi")

INFORMATAT E PËRGJITHSHME TË PUNËMARRËSIT

Gjenerale

Pozita: {{position}}
Lokacioni i vendit të punës: {{location}}
Paga në muaj: € {{salary}}
Paga është neto/bruto: {{salary_type}}
A aplikohet targeti/komisioni: {{target_agreement}}
Kohëzgjatja e periudhës provuese: {{probation}}
Lloji i Kontratës: {{contract_kind}}
Data e fillimit apo vazhdimit të marrdhënies së punës: {{start}}
Data e Përfundimit të marrdhënies së punës: {{end}}
Kohëzgjatja e periudhës për punësimin me kohë të caktuar: {{duration}} Muaj

Hollësitë administrative

Gjuha amtare: {{language}}
Mënyra e Pagesës së Pagës / Kompenzimit: {{payment_method}}
Sektori: {{sector}}
Detyrat dhe Përgjegjësitë: sipas aneks - it 1 dhe Kushteve te përgjithshme

Neni 2

Punëmarrësi kryen personalisht punën e ngarkuar si {{position}} duke respektuar urdhërat dhe udhëzimet e përgjithshme dhe të veçanta të punëdhënesit, si dhe punët tjera duke u mbeshtetur në aftësitë e tyre fizike dhe intelektuale, përjashtuar punët të cilat e vëjnë në rrezik jetën dhe shëndetin e tij.

Përgjegjësitë Kryesore të Punëmarrësit janë të përcaktuar me Rregulloren e Brendshme të Kompanisë.

Neni 3

Punëdhënesi dhe punëmarrësi janë pajtuar që orari i punës të jetë i caktueshëm sipas nevojës dhe kërkesave momentale të punëdhënësit. Punëmarrësit i takon pushimi ditor prej 30 minutash gjatë orarit të punës. Secili nga punëmarrësi e gëzon te drejtën e shfrytëzimit të pushimit javor së paku një ditë. Punëmarrësi realizon të drejtën në pushim vjetor sipas nenit 32 të Ligjit të punës.

Neni 4

Punëdhënesi dhe punëmarrësi u pajtuan që e ardhura mujore e punëmarrësit të jetë {{salary}} euro ({{salary_type}}), e cila shumë derdhet në llogarinë bankare të punëmarrësit më se largu me 15 të ç'do muaji vijues.

Neni 5

Kjo kontratë lidhet për ({{duration}}) muaj. Palët kontraktuese u pajtuan se data e fillimit (vazhdimit) të punës të jetë me {{start}} dhe do të zgjasë deri me datë: {{end}}. Punëmarrësit me kontratë të caktuar pune i pushon marrëdhenia e punës pas kalimit të afatit të paraparë me kontratë, (Neni 67 par.1 pika 1.3) pa marrë parasysh kerkesat.

Neni 6

Punëmarrësi obligohet që punët të cilat i vehen në ngarkim duhet t'i kryej me kujdes, duke përdorë sipas nevoje mjetet e punës, aparaturat dhe pajisjet e vëna në dispozicion. Punëmarrësi përgjigjet ndaj punëdhënesit për dëmin që i shkakton kur shkel detyrimet kontraktuale me dashje ose nga pakujdesia. I punësuari është përgjegjës edhe për kompenzimin e dëmit, nëse me fajin e tij i ka shkaktuar dëm palës së tretë, dëm të cilin punëdhënësi e ka kompenzuar.

Neni 7

Punëdhënesi dhe punëmarrësi i pranojnë të gjitha të drejtat, detyrimet dhe përgjegjësitë e parapara me dispozitat e Kodit të punës. Punëdhënesi obligohet t'i sigurojë mjetet e punës dhe zbatoje masat e mbrojtjes në punë, te cilat duhet të përdoren nga ana e punëmarrësve.

Neni 8

Punëdhënesi dhe punëmarrësi u pajtuan që ta respektojnë rregulloren interne të punës e cila është përpiluar nga organi udhëheqës i kompanisë ose njësisë punuese, e cila rregullore është në pajtim me Ligjin e punës në fuqi.

Neni 9

Secila nga palët mund ta shkëpusin kontratën e punës në mënyrë të njëanshme (Neni 69 par.1) ose me marrëveshje (68 par.1). Kur njëra nga palët e zgjidh kontratën pa respektuar afatin e njoftimit, zgjidhja trajtohet si zgjidhje e kontratës me efekt të menjehershëm. Punëdhënesi e shkëput kontratën për shkak të shkeljeve disiplinore të punëmarrësit në rastet kur: shkel detyrimet kontraktuale me faj të rëndë, si edhe rastet kur shkel detyrimet kontraktuale me faj të lehtë, në mënyrë të përsëritur, me gjithë paralajmërimin me shkrim të punëdhënësit (Neni 70). Çështjet të cilat palët nuk i kanë përfshirë në këtë kontratë në mënyrë analoge rregullohen me ligjin e punës.

Neni 10

Palët kontraktuese mosmarrëveshjet ndërmjet tyre mund t'i zgjidhin me marrëveshje, në të kundërtën ata mund t'i drejtohen Gjykatës Themelore në Prishtinë.

Neni 11

Pasi punëmarrësi u njoh me rregulloren e brendshme të kompanisë, me detyrat dhe kompetencat e tij, të dy palët ranë dakord dhe me dëshirë miratojnë këtë kontratë pune, e cila hyn në fuqi me datë: {{date}}

Neni 12

Kontrata është përpiluar në dy kopje me fuqi juridike të njëjtë, për secilën palë nga një kopje


Punëdhënësi:
Kodret Zeneli, Drejtor

Nënshkrimi: _______________________     Data: {{date}}

Vula e kompanisë (25hours SH.P.K, Prishtinë):



Punëmarrësi:
{{name}}
Emri/mbiemri i Punonjësit

Nënshkrimi: _______________________     Data: {{date}}
$body$,
  $ph$[
    {"key":"name","label":"Name","kind":"computed","maps_to":"name"},
    {"key":"id_number","label":"Ausweisnummer","kind":"field","maps_to":"id_number"},
    {"key":"position","label":"Position","kind":"field","maps_to":"position"},
    {"key":"location","label":"Standort","kind":"field","maps_to":"location"},
    {"key":"salary","label":"Gehalt","kind":"field","maps_to":"fixed_salary"},
    {"key":"salary_type","label":"Brutto/Netto","kind":"nested","maps_to":"contract.salary_type"},
    {"key":"target_agreement","label":"Zielvereinbarung (ja/nein)","kind":"nested","maps_to":"contract.target_agreement"},
    {"key":"probation","label":"Probezeit","kind":"nested","maps_to":"contract.probation"},
    {"key":"contract_kind","label":"Vertragsart","kind":"nested","maps_to":"contract.kind"},
    {"key":"start","label":"Beginn","kind":"nested","maps_to":"contract.start"},
    {"key":"end","label":"Ende","kind":"nested","maps_to":"contract.end"},
    {"key":"duration","label":"Laufzeit","kind":"computed","maps_to":"duration"},
    {"key":"language","label":"Sprache","kind":"nested","maps_to":"contract.language"},
    {"key":"payment_method","label":"Zahlungsweise","kind":"nested","maps_to":"contract.payment_method"},
    {"key":"sector","label":"Sektor","kind":"nested","maps_to":"contract.sector"},
    {"key":"date","label":"Datum (heute)","kind":"computed","maps_to":"today"}
  ]$ph$::jsonb,
  true
);
