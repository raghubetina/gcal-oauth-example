# Learnings: Building Google Calendar OAuth in Rails

This document captures the journey of building this OAuth implementation - the initial attempts, problems encountered, rabbit holes, and final solutions.

## The Goal

Create a beginner-friendly template that students can clone to learn OAuth with Google Calendar. The key requirement: it should "just work" after cloning, with minimal friction.

## Initial Friction: DATABASE_URL

**Problem**: The original template required a `DATABASE_URL` environment variable, causing `bin/setup` to fail immediately.

**Root cause**: The `database.yml` used `ENV.fetch("DATABASE_URL")` which raises an error if the variable isn't set.

**Solution**: Changed development/test to use simple database names like `gcal_oauth_example_development` instead of requiring environment variables. Production can still use `DATABASE_URL`.

**Lesson**: Fail-fast with `ENV.fetch` is good for production secrets, but creates friction for development setup. Consider sensible defaults for dev.

## The OAuth Flow: More Complex Than Expected

### Attempt 1: Simple `find_or_create_by`

Started with the standard Devise OmniAuth pattern:

```ruby
def self.from_omniauth(auth)
  find_or_create_by(provider: auth.provider, uid: auth.uid) do |user|
    user.email = auth.info.email
    user.password = Devise.friendly_token[0, 20]
    user.google_access_token = auth.credentials.token
  end
end
```

**Problem**: The block only runs for *new* records. Returning users don't get their token updated.

**Why this matters**: Access tokens expire or change. If we don't update the token on each sign-in, API calls will eventually fail.

### Attempt 2: Update token after find_or_create

```ruby
def self.from_omniauth(auth)
  user = find_or_create_by(provider: auth.provider, uid: auth.uid) do |new_user|
    new_user.email = auth.info.email
    new_user.password = Devise.friendly_token[0, 20]
  end

  user.update(google_access_token: auth.credentials.token)
  user
end
```

**Problem**: This would create duplicate users if someone signed up with email first, then tried to sign in with Google using the same email.

### Final Solution: Three-tier lookup

```ruby
def self.from_omniauth(auth)
  user = find_by(provider: auth.provider, uid: auth.uid)  # Returning OAuth user
  user ||= find_by(email: auth.info.email)                 # Existing email user
  user ||= new(email: auth.info.email, password: Devise.friendly_token[0, 20])

  user.provider = auth.provider
  user.uid = auth.uid
  user.google_access_token = auth.credentials.token
  user.save
  user
end
```

**Why this works**:
1. First checks for existing OAuth user (returning visitor)
2. Falls back to email match (links Google to existing account)
3. Only creates new user if neither exists
4. Always updates token regardless of path taken

## Google Cloud Console: Death by a Thousand Cuts

### Problem 1: "Access blocked" error

**Symptom**: "Access blocked: [App name] has not completed the Google verification process"

**Cause**: App is in "Testing" mode and user's email isn't in the test users list.

**Solution**: Add your email to OAuth consent screen > Test users.

**Lesson**: Google's security model is opt-in for unverified apps. Document this prominently.

### Problem 2: "Insufficient authentication scopes"

**Symptom**: OAuth worked, but Calendar API calls failed with 403.

**Initial diagnosis**: Thought the token was stale or the scope wasn't in Devise config.

**Actual cause**: Two separate issues:
1. Scope wasn't added to OAuth consent screen in Google Cloud Console
2. Google caches granted scopes - signing in again doesn't ask for new ones

**Solution**:
1. Add `prompt: "consent"` to force re-consent every time
2. Add `access_type: "offline"` for refresh tokens
3. Handle API errors gracefully by signing user out

### Problem 3: "Google Calendar API has not been used in project"

**Symptom**: OAuth worked, scopes were correct, but API calls still failed.

**Cause**: The Calendar API wasn't enabled in Google Cloud Console. OAuth scopes and API enablement are separate things!

**Solution**: APIs & Services > Library > Google Calendar API > Enable

**Lesson**: There are THREE things that must be configured in Google Cloud:
1. OAuth consent screen (with scopes)
2. OAuth credentials (client ID and secret)
3. API enablement (actually turn on the Calendar API)

## Error Handling: The Redirect Loop

**Problem**: When API calls failed, we redirected to sign-in. But if the underlying issue wasn't fixed (e.g., API not enabled), they'd sign in successfully and immediately hit the error again.

**Attempt 1**: Redirect directly to OAuth authorize path

```ruby
redirect_to user_google_oauth2_omniauth_authorize_path
```

**Problem**: OmniAuth requires POST for security (CSRF protection). GET requests show "Not found. Authentication passthru."

**Final solution**: Redirect to sign-in page with a message

```ruby
rescue Google::Apis::ClientError
  sign_out current_user
  redirect_to new_user_session_path,
    alert: "We need permission to access your calendar. Please sign in again."
end
```

**Trade-off**: This can still loop if the issue is configuration (API not enabled). But at least the user sees the sign-in page and can check their setup rather than an error page.

## Key Takeaways

1. **OAuth is not just one thing** - It involves OAuth consent screen, credentials, API enablement, scopes, and token management. Each can fail independently.

2. **Tokens are ephemeral** - Always update the access token on sign-in, not just on user creation.

3. **Google caches consent** - Once a user grants scopes, Google remembers. Use `prompt: "consent"` to force re-asking if you change scopes.

4. **fail gracefully** - API errors will happen. Catch them and guide users to re-authenticate rather than showing stack traces.

5. **Test users are required** - Unverified apps in testing mode only work for explicitly listed test users.

6. **Document the gotchas** - Many OAuth tutorials skip the Google Cloud Console setup or assume it's obvious. It's not. Add screenshots and explicit warnings.

## What We'd Do Differently

1. **Start with the Google Cloud setup** - We should have configured everything in Google Cloud Console before writing any code. Would have caught the "API not enabled" issue earlier.

2. **Add a health check endpoint** - A simple endpoint that tests the Calendar API could help diagnose issues without the auth redirect loop.

3. **Consider refresh tokens** - We store `access_token` but not `refresh_token`. Access tokens expire after an hour. For a real app, we'd need to handle token refresh.

4. **Better error messages** - The `rescue Google::Apis::ClientError` catches everything. We could parse the error to give more specific guidance (API not enabled vs. wrong scopes vs. expired token).
