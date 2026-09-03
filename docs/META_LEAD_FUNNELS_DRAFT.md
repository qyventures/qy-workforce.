# QY Workforce Meta lead funnels — DRAFT / PREVIEW ONLY

No campaign in this document is approved for publishing. **Do not launch or incur Meta spend without explicit approval.** Placeholder budget for planning: **S$10/day per campaign**.

## Employer acquisition campaign

**Objective:** Leads  
**Primary destination:** https://qyworkforce.com/employers  
**Market:** Singapore  
**CTA options:** Request Workers / Get Manpower / Speak to QY Workforce  
**Core promise boundary:** Fast, flexible manpower support with vetted/ready workers, attendance visibility and operational follow-up. Do not state or imply guaranteed fulfilment, guaranteed attendance, guaranteed worker quality, employment eligibility, or fixed deployment time unless separately confirmed.

### A/B test angles

#### A — Urgent manpower gaps
Primary text 1: Short on manpower for an upcoming shift or busy period? Tell QY Workforce the roles, headcount, location and schedule you need. We help employers source and coordinate flexible frontline workers across cleaning, F&B, hospitality, banquet, events, retail and promotions.

Primary text 2: Staff shortage affecting operations? QY Workforce helps businesses respond to urgent manpower gaps with flexible worker deployment and clearer attendance visibility. Share your requirement and our team will follow up.

Headline options: `Need manpower urgently?` / `Fill frontline staffing gaps` / `Request workers for your next shift`

#### B — Flexible workers without permanent headcount
Primary text 1: Need more hands without adding permanent headcount? Use flexible workers for peaks, events, leave cover and changing operational demand. QY Workforce supports deployment planning, worker coordination and attendance tracking.

Primary text 2: Scale manpower up or down around actual demand. Share your role, headcount and shift requirements with QY Workforce and our team will assess suitable flexible staffing options.

Headline options: `Flexible manpower when demand changes` / `Scale frontline staffing flexibly` / `Extra manpower without permanent headcount`

#### C — Cleaning / F&B / hospitality deployment
Primary text 1: Hiring cleaners, service crew, banquet staff or hospitality workers for upcoming shifts? QY Workforce supports frontline manpower deployment across cleaning, F&B, hotels, banquet, events, retail and promotions.

Primary text 2: One manpower partner for multiple frontline roles. Tell us where, when and how many workers you need, plus any role or attire requirements. QY Workforce will review the requirement and follow up.

Headline options: `Frontline workers for your operations` / `Cleaning, F&B & hospitality manpower` / `Request flexible frontline staff`

#### D — Reduce no-show / attendance risk
Primary text 1: Manpower is only useful when you can see what is happening on the ground. QY Workforce combines worker deployment with attendance visibility, exception handling and operational follow-up to help teams manage staffing risk.

Primary text 2: Need better visibility over who is assigned, checked in and where gaps remain? QY Workforce helps employers coordinate flexible workers with attendance and fulfilment tracking built into operations.

Headline options: `Better visibility over every shift` / `Manage attendance and staffing gaps` / `More reliable manpower operations`

### Lead form flow

Use a high-intent employer form. Required fields unless noted:
1. Name
2. Company
3. Contact number
4. Email
5. Deployment timeline: `Today / 1–3 days / Within 1 week / 1–4 weeks / Planning ahead`
6. Worker role(s)
7. Headcount
8. Location / site
9. Shift / schedule
10. Optional requirements: attire, experience, certifications, language, VIP/special instructions or other operational needs
11. **PDPA consent checkbox (required):** consent to QY Workforce collecting and using submitted information to respond to the manpower enquiry and manage the business relationship, with link to https://qyworkforce.com/privacy
12. **WhatsApp consent checkbox (optional, explicit and unticked by default):** consent to receive WhatsApp follow-up about this enquiry from QY Workforce. Users can opt out by replying STOP.

Thank-you screen: `Thanks — your manpower request has been received. Our team will review the requirement and follow up using the contact details you provided.` Do not promise a response or deployment time that operations has not approved.

### Tracking parameters

Use consistent UTMs on every ad URL:
`https://qyworkforce.com/employers?utm_source=meta&utm_medium=paid_social&utm_campaign=qyw_employer_acquisition_sg&utm_content={{angle}}_{{creative}}&utm_term={{audience}}`

Recommended internal fields persisted with each lead: `source=meta`, `campaign=qyw_employer_acquisition_sg`, `campaign_angle`, `creative_id`, `ad_id`, `adset_id`, `campaign_id`, `landing_path`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`, `utm_term`, `submitted_at`, `pdpa_consent_at`, `whatsapp_opt_in_at`.

### Conversion events

Plan and validate these events before launch:
- `ViewEmployerLanding` — employer landing page loaded
- `StartEmployerLead` — first meaningful employer-form interaction
- `SubmitEmployerLead` — server-confirmed lead accepted into Supabase; primary campaign conversion
- `EmployerWhatsAppOptIn` — explicit WhatsApp opt-in captured; secondary conversion only
- `QualifiedEmployerLead` — qualification criteria met in CRM/Supabase; offline/downstream event, not client-declared
- `EmployerMeetingBooked` — BD meeting outcome recorded; downstream value signal

Never fire `SubmitEmployerLead` only from a client button click. Treat the server-confirmed Supabase write as the source of truth and deduplicate browser/server signals using a stable event ID where Meta CAPI is later enabled.

### Creative briefs

**Creative 1 — Urgent gap:** 4:5 static/mobile-first. Operations manager viewing a shift roster with an obvious staffing gap; clean Singapore workplace context; minimal overlay: `Need manpower for your next shift?` Secondary line: `Cleaning • F&B • Hospitality • Events • Retail`. CTA lock-up: `Request Workers`.

**Creative 2 — Flexible headcount:** 4:5 static. Split visual showing busy vs normal operation; overlay: `Scale manpower around demand`. Avoid savings claims or worker-count guarantees.

**Creative 3 — Multi-role:** 4:5 static/carousel. Separate panels for cleaner, F&B/service crew, banquet/hospitality, promoter/retail. Overlay: `Flexible frontline workers for your operations`.

**Creative 4 — Attendance visibility:** 4:5 static. Supervisor-style operations dashboard visual showing assigned / checked-in / gap status without displaying real personal data. Overlay: `See staffing gaps earlier` and `Deployment + attendance visibility`.

All creatives should be readable without sound, avoid depicting unsafe work practices, avoid claims such as `100% attendance`, `instant workers`, `guaranteed workers`, or `same-day guaranteed deployment`.

### Audience hypotheses for testing

Keep targeting broad enough for Meta optimisation while separating high-value hypotheses for reporting: hospitality/hotel operations, F&B operators, facilities/cleaning, events/banquet, retail/promotions, and general SME operations/HR. Exclude job-seeker messaging from employer ad sets. Do not infer sensitive characteristics or employment eligibility from targeting.

## Lead routing and qualification

**System of record:** Supabase. Store the employer form payload, consent timestamps, campaign/tracking attributes, qualification state and communication history there first.  
**BD handoff:** mirror/dedupe qualified lead fields into Google Sheet **QY Workforce Lead Pipeline**.  
**WhatsApp:** only leads with explicit WhatsApp opt-in may enter automated qualification. Intended QY Workforce production sender: **+65 8022 7816**. Support STOP/opt-out immediately and retain consent/opt-out timestamps.  

The qualification assistant may clarify worker roles, headcount, deployment timeline, location/site, shift pattern, attire, experience/certification needs and unique requirements. It may summarize and score urgency/completeness. It must not promise pricing, guaranteed fulfilment, employment, worker eligibility or deployment. Sensitive identity documents and credentials must not be requested over WhatsApp.

Suggested employer pipeline statuses: `new -> contacted -> qualifying -> qualified -> meeting/proposal -> won/lost`, with owner, next action and next follow-up timestamp. Failed Google Sheet sync must not lose the Supabase lead; retry asynchronously and surface sync state for BD/ops.

## Worker campaign

Worker acquisition remains draft-only and secondary to the current employer campaign. Existing worker messaging should retain separate PDPA consent and optional WhatsApp opt-in, with employment eligibility verified separately rather than inferred from advertising.
