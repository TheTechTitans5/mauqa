-- Mauqa seed data
-- 1) Reference data (categories, institutions) — safe for production.
-- 2) Official source registry — real organisations, but every connector is "awaiting_authorization":
--    no public API has been confirmed for any of them. Nothing is fetched until an admin configures it.
-- 3) DEMO opportunities — fictional organisations, is_demo = true, never "verified",
--    and links point at the reserved example.org domain. Remove with: select public.purge_demo_data();

-- ------------------------------------------------------------------ 1. categories
insert into public.opportunity_categories (slug, name_en, name_ur, icon, color_hex, sort_order) values
  ('scholarships', 'Scholarships', 'وظائف', 'school', '#16B8A6', 1),
  ('financial_aid', 'Financial aid', 'مالی امداد', 'payments', '#16B8A6', 2),
  ('fellowships', 'Fellowships', 'فیلوشپس', 'workspace_premium', '#7966D9', 3),
  ('internships', 'Internships', 'انٹرن شپس', 'badge', '#F5B94C', 4),
  ('jobs', 'Jobs', 'ملازمتیں', 'work', '#F07878', 5),
  ('graduate_programs', 'Graduate programs', 'گریجویٹ پروگرامز', 'stars', '#7966D9', 6),
  ('apprenticeships', 'Apprenticeships', 'اپرنٹس شپس', 'construction', '#F5B94C', 7),
  ('government_schemes', 'Government schemes', 'سرکاری اسکیمیں', 'account_balance', '#101D35', 8),
  ('youth_programs', 'Youth programs', 'نوجوانوں کے پروگرام', 'groups', '#16B8A6', 9),
  ('skills_development', 'Skills development', 'ہنر مندی کے پروگرام', 'psychology', '#7966D9', 10),
  ('free_training', 'Free training courses', 'مفت تربیتی کورسز', 'menu_book', '#16B8A6', 11),
  ('certifications', 'Certifications', 'سرٹیفیکیشنز', 'verified', '#F5B94C', 12),
  ('entrepreneurship', 'Entrepreneurship programs', 'کاروباری پروگرام', 'rocket_launch', '#F07878', 13),
  ('startup_funding', 'Startup funding', 'اسٹارٹ اپ فنڈنگ', 'savings', '#F07878', 14),
  ('business_grants', 'Business grants', 'کاروباری گرانٹس', 'storefront', '#F5B94C', 15),
  ('agriculture', 'Agriculture & farmer schemes', 'زراعت اور کسان اسکیمیں', 'agriculture', '#16B8A6', 16),
  ('women_empowerment', 'Women empowerment', 'خواتین کو بااختیار بنانے کے پروگرام', 'diversity_3', '#7966D9', 17),
  ('disability_support', 'Disability support', 'معذور افراد کے لیے معاونت', 'accessible', '#16B8A6', 18),
  ('research_grants', 'Research grants', 'تحقیقی گرانٹس', 'science', '#7966D9', 19),
  ('exchange_programs', 'Exchange programs', 'تبادلہ پروگرامز', 'sync_alt', '#F5B94C', 20),
  ('study_abroad', 'Study abroad', 'بیرون ملک تعلیم', 'flight_takeoff', '#F07878', 21),
  ('competitions', 'Competitions', 'مقابلے', 'emoji_events', '#F5B94C', 22),
  ('conferences', 'Conferences', 'کانفرنسز', 'campaign', '#7966D9', 23),
  ('volunteer', 'Volunteer programs', 'رضاکارانہ پروگرام', 'volunteer_activism', '#16B8A6', 24),
  ('community_development', 'Community development', 'کمیونٹی ترقیاتی پروگرام', 'diversity_1', '#101D35', 25)
on conflict (slug) do nothing;

-- ------------------------------------------------------------------ institutions (names only; recognition status not asserted)
insert into public.institutions (name, short_name, city, province, institution_type) values
  ('National University of Sciences and Technology', 'NUST', 'Islamabad', 'Islamabad Capital Territory', 'university'),
  ('Quaid-i-Azam University', 'QAU', 'Islamabad', 'Islamabad Capital Territory', 'university'),
  ('COMSATS University Islamabad', 'CUI', 'Islamabad', 'Islamabad Capital Territory', 'university'),
  ('Lahore University of Management Sciences', 'LUMS', 'Lahore', 'Punjab', 'university'),
  ('University of the Punjab', 'PU', 'Lahore', 'Punjab', 'university'),
  ('University of Engineering and Technology, Lahore', 'UET Lahore', 'Lahore', 'Punjab', 'university'),
  ('University of Karachi', 'UoK', 'Karachi', 'Sindh', 'university'),
  ('NED University of Engineering and Technology', 'NED', 'Karachi', 'Sindh', 'university'),
  ('University of Peshawar', 'UoP', 'Peshawar', 'Khyber Pakhtunkhwa', 'university'),
  ('University of Balochistan', 'UoB', 'Quetta', 'Balochistan', 'university'),
  ('National University of Computer and Emerging Sciences', 'FAST-NUCES', 'Islamabad', 'Islamabad Capital Territory', 'university'),
  ('Karakoram International University', 'KIU', 'Gilgit', 'Gilgit-Baltistan', 'university')
on conflict (name) do nothing;

-- ------------------------------------------------------------------ 2. official source registry (not connected)
insert into public.organizations (name, slug, org_type, website, official_domains, description, is_verified) values
  ('Higher Education Commission Pakistan', 'hec', 'government', 'https://www.hec.gov.pk', '{hec.gov.pk}',
   'Federal regulator of higher education. Publishes scholarship announcements.', false),
  ('National Jobs Portal (National IT Board)', 'njp', 'government', 'https://www.njp.gov.pk', '{njp.gov.pk}',
   'Official federal government job listings portal operated by the National Information Technology Board.', false),
  ('Pakistan Scientific & Technological Information Centre', 'pastic', 'government', 'https://www.pastic.gov.pk', '{pastic.gov.pk}',
   'Ministry of Science & Technology body that runs a national trainings portal.', false),
  ('Pakistan Digital Authority', 'pda', 'government', null, '{}',
   'Statutory body under the Digital Nation Pakistan Act 2025. Official website domain to be confirmed by an admin.', false)
on conflict (slug) do nothing;

insert into public.data_sources (organization_id, name, source_type, base_url, config, integration_status, authorization_notes,
                                 sync_interval_minutes, rate_limit_per_minute, is_enabled)
select o.id, s.name, s.stype::public.source_type, s.base_url, s.config::jsonb, 'awaiting_authorization', s.notes, 1440, 6, false
  from (values
    ('hec', 'HEC scholarship announcements', 'web_monitor', 'https://www.hec.gov.pk',
     '{"list_url": null, "item_selector": null, "fields": {}}',
     'No public API confirmed. Before enabling: review hec.gov.pk terms of use and robots.txt, set list_url to the official scholarships page, define selectors, and record written permission if required. Alternative: manual admin entry from official PDFs.'),
    ('hec', 'HEC announcement PDFs', 'pdf', 'https://www.hec.gov.pk',
     '{"pdf_urls": [], "ocr": false}',
     'Add specific official PDF URLs. Extracted fields always go to the review queue.'),
    ('njp', 'National Jobs Portal listings', 'web_monitor', 'https://www.njp.gov.pk',
     '{"list_url": null, "item_selector": null, "fields": {}}',
     'No public API confirmed. Request data-sharing access from NITB (info@njp.gov.pk) or configure authorised monitoring after reviewing terms and robots.txt. Do not automate account sign-in.'),
    ('pastic', 'PASTIC trainings portal', 'web_monitor', 'https://www.pastic.gov.pk',
     '{"list_url": null, "item_selector": null, "fields": {}}',
     'No public API confirmed. Configure after reviewing site terms; trainings portal requires member accounts for registration (never automate).'),
    ('pda', 'Pakistan Digital Authority announcements', 'manual', null, '{}',
     'Official domain not yet confirmed. Use manual entry until an admin verifies the official website.')
  ) as s(org_slug, name, stype, base_url, config, notes)
  join public.organizations o on o.slug = s.org_slug
 where not exists (select 1 from public.data_sources d where d.name = s.name);

-- ------------------------------------------------------------------ guides & interview questions (original content)
insert into public.guides (slug, category, title_en, title_ur, body_en, body_ur, is_published, sort_order) values
  ('scholarship-application-basics', 'scholarship', 'How to prepare a strong scholarship application', 'مضبوط اسکالرشپ درخواست کیسے تیار کریں',
   E'1. Read the official announcement twice and list every eligibility condition.\n2. Collect documents early: CNIC/B-Form, transcripts, domicile, income certificate, photographs.\n3. Get documents attested where the announcement asks for it.\n4. Write your statement around a specific goal and evidence of effort.\n5. Ask referees at least three weeks before the deadline.\n6. Submit only through the official portal named in the announcement, and keep your submission confirmation.\n\nWarning: genuine scholarships rarely charge a fee to apply. Be careful with anyone asking for payment to "guarantee" selection.',
   E'1. سرکاری اعلان کو دو بار پڑھیں اور اہلیت کی ہر شرط لکھ لیں۔\n2. دستاویزات پہلے سے جمع کریں: شناختی کارڈ/ب فارم، ٹرانسکرپٹ، ڈومیسائل، آمدنی کا سرٹیفکیٹ، تصاویر۔\n3. جہاں اعلان میں کہا گیا ہو وہاں تصدیق کروائیں۔\n4. اپنا بیان ایک واضح مقصد اور محنت کے ثبوت کے ساتھ لکھیں۔\n5. سفارشی خطوط آخری تاریخ سے کم از کم تین ہفتے پہلے مانگیں۔\n6. صرف اعلان میں دیے گئے سرکاری پورٹل سے درخواست دیں اور تصدیق محفوظ رکھیں۔\n\nخبردار: اصل وظائف عموماً درخواست کی فیس نہیں لیتے۔ انتخاب کی "ضمانت" کے بدلے رقم مانگنے والوں سے محتاط رہیں۔',
   true, 1),
  ('internship-application-basics', 'internship', 'Landing your first internship', 'پہلی انٹرن شپ کیسے حاصل کریں',
   E'- Keep a one-page CV focused on projects and coursework.\n- Tailor the first three lines of your CV to each role.\n- Show proof: GitHub, portfolio, or a short project write-up.\n- Apply in the first week a role opens; many teams review on a rolling basis.\n- Track every application in My Journey and set a follow-up reminder 7–10 days after applying.',
   E'- ایک صفحے کا سی وی رکھیں جس میں پروجیکٹس اور کورس ورک نمایاں ہوں۔\n- ہر عہدے کے لیے سی وی کی پہلی تین سطریں تبدیل کریں۔\n- ثبوت دکھائیں: گٹ ہب، پورٹ فولیو یا مختصر پروجیکٹ رپورٹ۔\n- عہدہ کھلنے کے پہلے ہفتے میں درخواست دیں۔\n- ہر درخواست کو "میرا سفر" میں محفوظ کریں اور 7 سے 10 دن بعد یاد دہانی لگائیں۔',
   true, 2),
  ('cv-writing', 'cv', 'Writing a CV recruiters can scan in 30 seconds', 'ایسا سی وی جو 30 سیکنڈ میں پڑھا جا سکے',
   E'Structure: contact line → short profile → education → experience/projects → skills → certifications.\nUse action verbs and numbers ("reduced report time by 40%").\nAvoid photos, CNIC numbers and full home address unless the employer explicitly requests them.\nExport as PDF and name the file Firstname-Lastname-CV.pdf.',
   E'ترتیب: رابطہ → مختصر تعارف → تعلیم → تجربہ/پروجیکٹس → مہارتیں → سرٹیفیکیشنز۔\nعملی الفاظ اور اعداد استعمال کریں۔\nجب تک ادارہ نہ مانگے، تصویر، شناختی کارڈ نمبر اور مکمل پتہ نہ لکھیں۔\nپی ڈی ایف میں محفوظ کریں۔',
   true, 3),
  ('spot-a-scam', 'tips', 'How to spot a fake opportunity', 'جعلی موقع کی پہچان کیسے کریں',
   E'Red flags: payment requested to "process" or "guarantee" selection; links that are not on the organisation''s official domain; WhatsApp-only contact; requests for your bank PIN or portal password; deadlines that pressure you to pay today.\nIn Mauqa, use "Report opportunity" if something looks wrong — our team reviews every report.',
   E'خطرے کی علامات: انتخاب کی "ضمانت" کے لیے رقم کا مطالبہ؛ ایسے لنکس جو ادارے کی سرکاری ویب سائٹ پر نہ ہوں؛ صرف واٹس ایپ پر رابطہ؛ بینک پن یا پورٹل پاس ورڈ مانگنا؛ آج ہی ادائیگی کا دباؤ۔\nکچھ غلط لگے تو "رپورٹ کریں" استعمال کریں۔',
   true, 4),
  ('statement-of-purpose', 'statement_of_purpose', 'Statement of purpose: a simple structure', 'مقصد کا بیان: آسان ڈھانچہ',
   E'Paragraph 1 – the problem or question that drives you.\nParagraph 2 – what you have already done about it (courses, projects, work).\nParagraph 3 – why this programme specifically (faculty, labs, curriculum).\nParagraph 4 – your plan after the programme and how it connects to Pakistan.\nKeep it within the word limit and have two people proofread it.',
   null, true, 5),
  ('interview-preparation', 'interview', 'Interview preparation checklist', 'انٹرویو کی تیاری کی فہرست',
   E'- Re-read the opportunity and your own application.\n- Prepare a 60-second introduction.\n- Prepare two stories using Situation–Task–Action–Result.\n- Prepare two questions to ask the panel.\n- For online interviews, test camera, mic and internet 30 minutes early.',
   null, true, 6)
on conflict (slug) do nothing;

insert into public.interview_questions (category, question_en, question_ur, guidance_en) values
  ('general', 'Tell us about yourself.', 'اپنے بارے میں بتائیں۔', 'Present → past → future in about one minute. Link it to the opportunity.'),
  ('general', 'Why do you want this opportunity?', 'آپ یہ موقع کیوں چاہتے ہیں؟', 'Mention two specific things about the programme and one personal goal.'),
  ('scholarship', 'How will this scholarship change your plans?', 'یہ وظیفہ آپ کے منصوبوں کو کیسے بدلے گا؟', 'Be concrete about what becomes possible and how you will give back.'),
  ('behavioural', 'Describe a time you failed and what you learned.', 'ایسا وقت بتائیں جب آپ ناکام ہوئے اور کیا سیکھا۔', 'Pick a real example, own it, focus on what you changed afterwards.'),
  ('internship', 'What project are you most proud of?', 'آپ کو کس پروجیکٹ پر سب سے زیادہ فخر ہے؟', 'Explain your role, the hardest part, and the measurable outcome.'),
  ('technical', 'Walk us through how you would debug a failing feature.', null, 'Reproduce, isolate, form a hypothesis, test, fix, add a regression test.');

-- ------------------------------------------------------------------ 3. DEMO data
create or replace function public.purge_demo_data() returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_system() or public.is_super_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  delete from opportunities where is_demo;
  delete from organizations where is_demo;
  delete from success_stories where is_demo;
  delete from data_sources where is_demo;
end $$;
revoke execute on function public.purge_demo_data() from public, anon;

do $$
declare
  o_found uuid; o_tech uuid; o_agri uuid; o_civic uuid;
  c record;
  op uuid; g uuid; g2 uuid;
  nust uuid; lums uuid;
begin
  select id into nust from institutions where short_name = 'NUST';
  select id into lums from institutions where short_name = 'LUMS';

  insert into organizations (name, slug, org_type, website, official_domains, description, is_demo) values
    ('[DEMO] Indus Future Foundation', 'demo-indus-future', 'ngo', 'https://example.org/indus-future', '{example.org}', 'Fictional organisation used for demo data.', true),
    ('[DEMO] Ravi Tech Labs', 'demo-ravi-tech', 'private', 'https://example.org/ravi-tech', '{example.org}', 'Fictional software company used for demo data.', true),
    ('[DEMO] Punjab Kisan Support Office', 'demo-kisan', 'government', 'https://example.org/kisan', '{example.org}', 'Fictional government office used for demo data.', true),
    ('[DEMO] Civic Youth Council', 'demo-civic-youth', 'ngo', 'https://example.org/civic-youth', '{example.org}', 'Fictional youth NGO used for demo data.', true)
  on conflict (slug) do nothing;
  select id into o_found from organizations where slug = 'demo-indus-future';
  select id into o_tech from organizations where slug = 'demo-ravi-tech';
  select id into o_agri from organizations where slug = 'demo-kisan';
  select id into o_civic from organizations where slug = 'demo-civic-youth';

  if exists (select 1 from opportunities where is_demo) then return; end if;

  -- 1. Need-and-merit scholarship (AND rules incl. income)
  insert into opportunities (title, organization_id, category_id, summary, description, benefits, funding_type, amount_text,
      amount_min_pkr, amount_max_pkr, education_levels, fields_of_study, max_age, eligibility_summary, application_procedure,
      selection_procedure, important_instructions, opening_date, deadline, status, tags, source_type, source_url,
      official_application_url, last_checked_at, verification_status, approval_status, is_published, is_featured, is_demo, recurrence_key)
  values ('[DEMO] Indus Need-cum-Merit Undergraduate Scholarship', o_found, (select id from opportunity_categories where slug = 'scholarships'),
      'Tuition plus monthly stipend for enrolled undergraduates from low-income households.',
      'Sample record for testing. Covers tuition and a monthly stipend for students enrolled in a bachelor programme in Pakistan.',
      'Full tuition, PKR 15,000 monthly stipend, mentoring sessions.', 'fully_funded', 'Tuition + PKR 15,000/month',
      180000, 400000, '{bachelor}', '{}', 25,
      'Enrolled bachelor students, CGPA 3.0+, household income up to PKR 100,000/month, age 25 or below.',
      'Apply online through the organisation''s portal and upload documents.',
      'Document screening → interview → final merit list.',
      'This is DEMO data. No fee is charged by genuine programmes of this type.',
      now() - interval '10 days', now() + interval '20 days', 'open', '{need-based,merit}', 'manual',
      'https://example.org/indus-future/scholarship', 'https://example.org/indus-future/apply', now(),
      'unverified', 'approved', true, true, true, 'demo-indus-ug-scholarship')
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, group_operator, sort_order) values (op, 'group', 'and', 0) returning id into g;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, is_mandatory, sort_order) values
    (op, g, 'criterion', 'education_level_in', '{"levels":["bachelor"]}', 'Studying a bachelor programme', true, 1),
    (op, g, 'criterion', 'enrollment_status_in', '{"statuses":["enrolled"]}', 'Currently enrolled', true, 2),
    (op, g, 'criterion', 'cgpa_min', '{"min":3.0,"scale":4.0}', 'CGPA 3.0 or above', true, 3),
    (op, g, 'criterion', 'income_max', '{"monthly_pkr":100000}', 'Household income up to PKR 100,000/month', true, 4),
    (op, g, 'criterion', 'age_range', '{"max":25}', 'Age 25 or below', true, 5),
    (op, g, 'criterion', 'documents_required', '{"categories":["transcript","cnic","income_certificate"]}', 'Transcript, CNIC/B-Form, income certificate', false, 6);
  insert into opportunity_documents (opportunity_id, category, label) values
    (op, 'transcript', 'Latest transcript'), (op, 'cnic', 'CNIC or B-Form'), (op, 'income_certificate', 'Household income certificate'),
    (op, 'photograph', 'Passport-size photograph');

  -- 2. Women in tech fellowship (AND with nested OR)
  insert into opportunities (title, organization_id, category_id, summary, description, benefits, funding_type, amount_text,
      amount_min_pkr, work_mode, education_levels, fields_of_study, required_skills, gender_eligibility,
      eligibility_summary, application_procedure, opening_date, deadline, status, tags, source_type, source_url,
      official_application_url, last_checked_at, verification_status, approval_status, is_published, is_featured, is_demo)
  values ('[DEMO] Women in Tech Fellowship', o_tech, (select id from opportunity_categories where slug = 'fellowships'),
      'Six-month paid fellowship for women in computing.', 'Sample record. Mentored product engineering fellowship.',
      'PKR 60,000/month, laptop, mentorship.', 'paid', 'PKR 60,000/month', 60000, 'hybrid',
      '{bachelor,master}', '{Computer Science,Software Engineering,Information Technology}', '{Python,JavaScript}', 'female',
      'Women studying or graduated in computing OR with Python/JavaScript skills.',
      'Submit CV and a short project link.', now() - interval '3 days', now() + interval '5 days', 'open', '{women,tech}', 'manual',
      'https://example.org/ravi-tech/fellowship', 'https://example.org/ravi-tech/fellowship/apply', now(),
      'unverified', 'approved', true, true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, group_operator) values (op, 'group', 'and') returning id into g;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, sort_order) values
    (op, g, 'criterion', 'gender_in', '{"genders":["female"]}', 'Open to women', 1);
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, group_operator, label, sort_order)
    values (op, g, 'group', 'or', 'Computing background', 2) returning id into g2;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, sort_order) values
    (op, g2, 'criterion', 'field_of_study_in', '{"fields":["Computer Science","Software Engineering","Information Technology"]}', 'Studying computing', 1),
    (op, g2, 'criterion', 'skills_required', '{"skills":["Python","JavaScript"],"mode":"any"}', 'Knows Python or JavaScript', 2);

  -- 3. University-specific internship (whitelist available)
  insert into opportunities (title, organization_id, category_id, summary, description, funding_type, amount_text, amount_min_pkr,
      work_mode, location_text, is_nationwide, provinces, cities, education_levels, required_skills, eligibility_summary,
      opening_date, deadline, status, tags, source_type, source_url, official_application_url, last_checked_at,
      verification_status, approval_status, is_published, is_demo)
  values ('[DEMO] Summer Software Internship (partner universities)', o_tech, (select id from opportunity_categories where slug = 'internships'),
      'Eight-week paid internship for students of partner universities.', 'Sample record. Backend, mobile and data tracks.',
      'paid', 'PKR 40,000/month', 40000, 'onsite', 'Lahore', false, '{Punjab}', '{Lahore}', '{bachelor}', '{Git,SQL}',
      'Students in semester 5–8 at NUST or LUMS.', now() - interval '1 day', now() + interval '40 days', 'open', '{summer,paid}', 'manual',
      'https://example.org/ravi-tech/internship', 'https://example.org/ravi-tech/internship/apply', now(),
      'unverified', 'approved', true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, group_operator) values (op, 'group', 'and') returning id into g;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, is_mandatory, sort_order) values
    (op, g, 'criterion', 'institution_whitelist', jsonb_build_object('list_available', true, 'institution_ids', jsonb_build_array(nust, lums),
        'names', jsonb_build_array('NUST', 'LUMS')), 'Partner universities only', true, 1),
    (op, g, 'criterion', 'semester_range', '{"min":5,"max":8}', 'Semester 5 to 8', true, 2),
    (op, g, 'criterion', 'skills_required', '{"skills":["Git","SQL"],"mode":"all"}', 'Git and SQL', false, 3);

  -- 4. Restricted programme whose institution list was NOT published → engine must return "unconfirmed"
  insert into opportunities (title, organization_id, category_id, summary, funding_type, education_levels, eligibility_summary,
      opening_date, deadline, status, source_type, source_url, official_application_url, last_checked_at,
      verification_status, approval_status, is_published, is_demo)
  values ('[DEMO] Research Assistantship (selected institutions)', o_found, (select id from opportunity_categories where slug = 'research_grants'),
      'Open only to "selected institutions" — the list has not been published.', 'paid', '{master,mphil}',
      'Selected institutions only (list not published).', now(), now() + interval '25 days', 'open', 'manual',
      'https://example.org/indus-future/ra', 'https://example.org/indus-future/ra/apply', now(),
      'unverified', 'approved', true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, group_operator) values (op, 'group', 'and') returning id into g;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, sort_order) values
    (op, g, 'criterion', 'education_level_in', '{"levels":["master","mphil"]}', 'Master/MPhil student', 1),
    (op, g, 'criterion', 'institution_whitelist', '{"list_available": false}', 'Selected institutions (list not published)', 2);

  -- 5. Farmer scheme with custom criterion
  insert into opportunities (title, organization_id, category_id, summary, description, funding_type, amount_text, is_nationwide,
      provinces, eligibility_summary, opening_date, deadline, status, tags, source_type, source_url, official_application_url,
      last_checked_at, verification_status, approval_status, is_published, is_featured, is_demo)
  values ('[DEMO] Small Farmer Input Support', o_agri, (select id from opportunity_categories where slug = 'agriculture'),
      'Subsidised seed and fertiliser for small landholders.', 'Sample record for agriculture schemes.',
      'not_applicable', 'Input subsidy', false, '{Punjab}', 'Farmers in Punjab with up to 12.5 acres.',
      now() - interval '5 days', now() + interval '2 days', 'open', '{farmers,subsidy}', 'manual',
      'https://example.org/kisan/inputs', 'https://example.org/kisan/inputs/apply', now(),
      'unverified', 'approved', true, true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, group_operator) values (op, 'group', 'and') returning id into g;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, sort_order) values
    (op, g, 'criterion', 'user_category_in', '{"categories":["farmer"]}', 'Registered as a farmer', 1),
    (op, g, 'criterion', 'province_in', '{"provinces":["Punjab"]}', 'Lives in Punjab', 2),
    (op, g, 'criterion', 'custom', '{"description":"Land holding up to 12.5 acres (verified by the scheme office)"}', 'Land holding up to 12.5 acres', 3);

  -- 6. Graduate job
  insert into opportunities (title, organization_id, category_id, summary, funding_type, amount_text, amount_min_pkr, amount_max_pkr,
      work_mode, location_text, is_nationwide, provinces, cities, education_levels, required_skills, min_experience_months,
      eligibility_summary, opening_date, deadline, status, tags, source_type, source_url, official_application_url, last_checked_at,
      verification_status, approval_status, is_published, is_demo)
  values ('[DEMO] Junior Data Analyst', o_tech, (select id from opportunity_categories where slug = 'jobs'),
      'Entry-level analyst role for recent graduates.', 'paid', 'PKR 120,000–160,000/month', 120000, 160000, 'remote',
      'Remote (Pakistan)', true, '{}', '{}', '{bachelor,master}', '{SQL,Excel,Python}', 6,
      'Graduate with 6+ months of internship or work experience in analytics.', now(), now() + interval '30 days', 'open', '{remote,graduate}', 'manual',
      'https://example.org/ravi-tech/careers/analyst', 'https://example.org/ravi-tech/careers/analyst/apply', now(),
      'unverified', 'approved', true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, group_operator) values (op, 'group', 'and') returning id into g;
  insert into opportunity_eligibility_rules (opportunity_id, parent_id, node_type, criterion_type, params, label, is_mandatory, sort_order) values
    (op, g, 'criterion', 'education_level_in', '{"levels":["bachelor","master"]}', 'Bachelor or master degree', true, 1),
    (op, g, 'criterion', 'enrollment_status_in', '{"statuses":["completed","awaiting_result"]}', 'Graduated (or awaiting result)', true, 2),
    (op, g, 'criterion', 'experience_min_months', '{"months":6,"kinds":["work","internship"]}', '6 months experience', true, 3),
    (op, g, 'criterion', 'skills_required', '{"skills":["SQL","Excel","Python"],"mode":"min","min_count":2}', 'Two of SQL, Excel, Python', false, 4);

  -- 7. Youth volunteer programme (upcoming)
  insert into opportunities (title, organization_id, category_id, summary, funding_type, min_age, max_age, eligibility_summary,
      opening_date, deadline, status, tags, source_type, source_url, official_application_url, last_checked_at,
      verification_status, approval_status, is_published, is_demo)
  values ('[DEMO] Community Literacy Volunteers', o_civic, (select id from opportunity_categories where slug = 'volunteer'),
      'Weekend volunteering to teach reading in community centres.', 'unpaid', 16, 30, 'Ages 16–30, any background.',
      now() + interval '6 days', now() + interval '50 days', 'upcoming', '{volunteer,youth}', 'manual',
      'https://example.org/civic-youth/literacy', 'https://example.org/civic-youth/literacy/apply', now(),
      'unverified', 'approved', true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, criterion_type, params, label) values
    (op, 'criterion', 'age_range', '{"min":16,"max":30}', 'Age 16 to 30');

  -- 8. Startup grant with application-fee warning (to exercise scam warnings)
  insert into opportunities (title, organization_id, category_id, summary, funding_type, amount_text, amount_max_pkr,
      eligibility_summary, opening_date, deadline, status, tags, has_application_fee, application_fee_pkr, source_type,
      source_url, official_application_url, last_checked_at, verification_status, approval_status, is_published, is_demo)
  values ('[DEMO] Early-stage Startup Grant', o_found, (select id from opportunity_categories where slug = 'startup_funding'),
      'Equity-free grant for early-stage founders. Demo listing includes an application fee to show the fee warning.',
      'partially_funded', 'Up to PKR 2,000,000', 2000000, 'Founders with a registered or registering business.',
      now() - interval '20 days', now() + interval '12 days', 'open', '{startup,grant}', true, 2500, 'manual',
      'https://example.org/indus-future/startup-grant', 'https://example.org/indus-future/startup-grant/apply', now(),
      'unverified', 'approved', true, true)
  returning id into op;
  insert into opportunity_eligibility_rules (opportunity_id, node_type, criterion_type, params, label) values
    (op, 'criterion', 'user_category_in', '{"categories":["entrepreneur","freelancer"]}', 'Founder or freelancer');

  -- 9. Disability support (no rules configured → engine returns unconfirmed)
  insert into opportunities (title, organization_id, category_id, summary, funding_type, eligibility_summary, opening_date, deadline,
      status, source_type, source_url, official_application_url, last_checked_at, verification_status, approval_status, is_published, is_demo)
  values ('[DEMO] Assistive Technology Support Fund', o_civic, (select id from opportunity_categories where slug = 'disability_support'),
      'Support towards assistive devices for students with disabilities.', 'partially_funded',
      'Students with disabilities (criteria not yet structured).', now(), now() + interval '60 days', 'open', 'manual',
      'https://example.org/civic-youth/assistive', 'https://example.org/civic-youth/assistive/apply', now(),
      'unverified', 'approved', true, true);

  -- 10. Closed opportunity (must never be recommended as active)
  insert into opportunities (title, organization_id, category_id, summary, funding_type, opening_date, deadline, status, source_type,
      source_url, official_application_url, last_checked_at, verification_status, approval_status, is_published, is_demo, recurrence_key)
  values ('[DEMO] Indus Need-cum-Merit Scholarship (previous cycle)', o_found, (select id from opportunity_categories where slug = 'scholarships'),
      'Previous cycle — kept for history.', 'fully_funded', now() - interval '380 days', now() - interval '340 days', 'closed', 'manual',
      'https://example.org/indus-future/scholarship-old', 'https://example.org/indus-future/apply', now() - interval '340 days',
      'expired', 'approved', true, true, 'demo-indus-ug-scholarship');

  insert into opportunity_cycles (recurrence_key, cycle_year, opened_on, deadline_on, notes) values
    ('demo-indus-ug-scholarship', extract(year from now())::int - 2, (now() - interval '740 days')::date, (now() - interval '700 days')::date, 'Demo history'),
    ('demo-indus-ug-scholarship', extract(year from now())::int - 1, (now() - interval '380 days')::date, (now() - interval '340 days')::date, 'Demo history');

  insert into success_stories (author_display_name, title, body, story_type, institution_name, status, published_at, is_demo) values
    ('[DEMO] Ayesha K.', 'How I organised my first scholarship application',
     'Sample story for testing. I kept every document in one folder, set reminders a week before the deadline and asked my teacher for a reference early. The interview felt much easier because I had practised my introduction.',
     'scholarship', 'Sample University', 'approved', now(), true);
end $$;
