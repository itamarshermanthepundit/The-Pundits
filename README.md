# The Pundits Online App

This folder is the online-ready version of the prediction game.

## Files

- `index.html` - player app
- `admin.html` - admin result entry page
- `cloud.js` - Supabase connection helpers
- `scoring.js` - scoring rules
- `supabase-schema.sql` - database tables and permissions
- `supabase-config.js` - live Supabase settings
- `assets/` - local images

## Setup

1. Create a Supabase project.
2. Open the Supabase SQL editor.
3. Run everything in `supabase-schema.sql`.
4. In Supabase, go to Project Settings > API.
5. Copy the Project URL and anon public key.
6. Paste them into `supabase-config.js`.
7. Publish this folder with Netlify or Vercel.

## Admin

After signing in once, set your profile as admin in Supabase:

```sql
update public.profiles
set is_admin = true
where email = 'YOUR_EMAIL_HERE';
```

Then open `/admin.html` on the deployed site.

## Current Scoring

- Correct group-stage position: 5 points
- Correct champion: 20 points
- Correct top scorer: 20 points
- Correct top assister: 20 points
- Correct Round of 32 winning side: 5 points
- Correct Round of 32 exact score: 10 points
