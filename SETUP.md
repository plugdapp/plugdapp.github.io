# Plug'd setup guide

Everything here is free. Do the parts in order. The examples use the GitHub username **plugdapp**. If you got a different username, use yours wherever you see `plugdapp`.

---

## Part 1: Set up the database (Supabase)

1. Go to **supabase.com** and open the **plugd** project.
2. In the left menu, click **SQL Editor**, then **New query**.
3. Open the file `supabase/schema.sql` from this folder, copy everything in it, and paste it into the box.
4. Click **Run**. You should see **Success. No rows returned.**
5. In the left menu, click **Authentication**, then **URL Configuration**.
6. **Site URL:** `https://plugdapp.github.io/`
7. Under **Redirect URLs**, click **Add URL** and type `https://plugdapp.github.io/**`, then click **Save**.
8. In the left menu, click **Project Settings**, then **API** (or click **Connect** at the top). Copy these two things into a note:
   - **Project URL** (it looks like `https://abcdefgh.supabase.co`)
   - **anon public** key (a long code starting with `eyJ`)

> The anon key is meant to be public. The security rules from step 4 protect the data.

---

## Part 2: Put the app online (GitHub Pages)

1. Sign in at **github.com**, click the **+** at the top right, then **New repository**.
2. **Repository name:** `plugdapp.github.io`
3. Choose **Public**, then click **Create repository**.
4. Click the link **uploading an existing file**.
5. Unzip the Plug'd folder on your computer. Drag **everything inside it** into the upload box, including the `.github` folder, then click **Commit changes**.
   - On a Mac, hidden folders like `.github` don't show up. If it didn't upload, see **Part 3, step 1** below to add it by hand.
6. (Already done for you: `config.js` has her Supabase address and publishable key filled in.)
7. Nothing to edit here.
8. Click **Settings** (top of the repository), then **Pages** in the left menu.
9. **Source:** `Deploy from a branch`. **Branch:** `main` and `/ (root)`. Click **Save**.
10. Wait about 2 minutes, then open **https://plugdapp.github.io**. Plug'd should load.

---

## Part 3: Turn on the keep-awake check (stops Supabase from pausing)

1. Only if `.github` didn't upload: click **Add file**, then **Create new file**. For the name, type `.github/workflows/keep-alive.yml`, paste in the contents of that file from this folder, and click **Commit changes**.
2. Click **Settings**, then **Secrets and variables**, then **Actions**.
3. Click **New repository secret**. **Name:** `SUPABASE_URL`. **Secret:** `https://dtdrsnvfyseutzhwfvjc.supabase.co` Click **Add secret**.
4. Click **New repository secret** again. **Name:** `SUPABASE_ANON_KEY`. **Secret:** the publishable key (`sb_publishable_dSgqJ-1ACCWlTvjwX4O39g_m_H9B55U`). Click **Add secret**.
5. Click the **Actions** tab. If GitHub asks, click **I understand my workflows, go ahead and enable them**.
6. Click **Keep Plug'd awake**, then **Run workflow**, then the green **Run workflow** button.
7. After about a minute, a green check mark means it works. From now on it runs by itself every 3 days.

---

## Part 4: Make your account the Plug'd admin

1. Open **https://plugdapp.github.io**, tap **Join**, and create your account.
2. Confirm your email with the link Supabase sends, then sign in and set up your profile.
3. In Supabase, open **SQL Editor**, then **New query**, paste this with your email in place of the example, and click **Run**:

```sql
insert into public.admins (user_id)
select id::text from auth.users where email = 'her-email@example.com';
```

4. Refresh the app. You now have **Make VIP**, **Add strike**, problem-report decisions, and the **Test mode** switch under **My Plugs**.

---

## Part 5: Put it on your phone

- **iPhone:** open the link in **Safari**, tap **Share**, then **Add to Home Screen**, then **Add**.
- **Android:** open the link in **Chrome**, tap **⋮**, then **Install app**.

The app also has a **Get the Plug'd app** button that shows these steps.

---

## Good to know

- **Sign-up emails:** Supabase's built-in email sender only sends a few emails per hour. That's fine for testing. Before launch, either connect a free email service under **Authentication > Emails > SMTP Settings**, or turn off **Confirm email** under **Authentication > Sign In / Providers > Email**.
- **Test mode:** under **My Plugs**, turn on **Test mode**. Use a second email address as a second account to play the other side of a booking. The test buttons let you move a gig to yesterday and skip ahead 48 business hours. **Reset test data** deletes everything created while test mode was on.
- **Plug'd Pay is a preview.** No real cards are charged until a Stripe account is connected.
- **If Supabase ever pauses anyway:** open supabase.com and click **Restore project**. Nothing is lost.
- **When it gets big:** Supabase Pro is $25 a month and removes the pause. GitHub hosting stays free.
