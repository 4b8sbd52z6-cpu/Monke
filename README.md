# Monke

Static site deployed with GitHub Pages. The shared chalkboard and mail use the
Supabase project configured in `index.html`; the browser uses its public
publishable key, never a `service_role` key.

## Supabase setup

1. In the Supabase SQL Editor, run [`supabase/schema.sql`](./supabase/schema.sql).
2. In Authentication settings, enable **Allow anonymous sign-ins**. This lets
   visitors send letters without exposing the mailbox.
3. In Authentication > Users, create the owner's email/password user.
4. Add that account to the owner allowlist in the SQL Editor, replacing the
   placeholder with the exact account email:

   ```sql
   insert into public.mail_owners (user_id)
   select id from auth.users where email = 'YOUR_OWNER_EMAIL'
   on conflict do nothing;
   ```

5. Deploy the site. Visitors can draw and send letters; use **Monke? Sign in
   to read the mail.** below the letter form to open the owner mailbox.

The board is shared with anyone who can access the site. Letters can only be
read by their sender and the account explicitly listed in `mail_owners`.
Anonymous visitors are limited to 30 letters per Supabase anonymous account.
