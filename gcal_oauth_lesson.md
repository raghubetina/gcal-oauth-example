# Google Calendar OAuth with Rails

In this guide, we'll build a Rails app that lets users sign in with their Google account and view their upcoming Google Calendar events.

By the end, you'll have an app where users can:
1. Sign in with their Google account (no password needed!)
2. See a list of their upcoming calendar events

## Prerequisites

This guide assumes you're starting with a fresh Rails 8 app. We'll set up everything from scratch, including Devise for authentication.

## Step 1: Install Devise

First, add the Devise gem to your `Gemfile` if it's not already there:

```ruby
# Gemfile

gem "devise"
```

Then run:

```
bundle install
```

Now run the Devise installer:

```
bin/rails generate devise:install
```

This creates two files:
- `config/initializers/devise.rb` - the main configuration file
- `config/locales/devise.en.yml` - English translations for flash messages

## Step 2: Generate the User model

Next, generate a User model with Devise:

```
bin/rails generate devise User
```

This creates:
- A migration file to create the `users` table
- The `User` model with Devise modules included
- A route `devise_for :users`

Run the migration:

```
bin/rails db:migrate
```

Now you have a working authentication system! Users can sign up and sign in at `/users/sign_up` and `/users/sign_in`.

But we want users to sign in with Google instead of a password. Let's set that up next.

## Step 3: Add OmniAuth gems

[OmniAuth](https://github.com/omniauth/omniauth) is a library that standardizes authentication across many providers (Google, GitHub, Facebook, etc.). We need two gems:

```ruby
# Gemfile

gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
```

- `omniauth-google-oauth2` - handles the Google-specific OAuth flow
- `omniauth-rails_csrf_protection` - required security gem that protects against CSRF attacks

Run:

```
bundle install
```

## Step 4: Register your app with Google

Before we can configure our app, we need to get credentials from Google. This involves:
1. Creating a project in Google Cloud Console
2. Enabling the Google Calendar API
3. Creating OAuth credentials

### Create a Google Cloud project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Click the project dropdown at the top of the page and click "New Project"
3. Give your project a name (e.g., "My Calendar App") and click "Create"
4. Wait for the project to be created, then make sure it's selected in the dropdown

### Enable the Google Calendar API

1. In the left sidebar, go to "APIs & Services" > "Library"
2. Search for "Google Calendar API"
3. Click on it and then click "Enable"

### Configure the OAuth consent screen

Before creating credentials, you need to configure what users see when they authorize your app:

1. Go to "APIs & Services" > "OAuth consent screen"
2. Select "External" (unless you have a Google Workspace organization) and click "Create"
3. Fill in the required fields:
   - **App name**: Your app's name (e.g., "My Calendar App")
   - **User support email**: Your email address
   - **Developer contact information**: Your email address
4. Click "Save and Continue"
5. On the "Scopes" page, click "Add or Remove Scopes" and add:
   - `.../auth/userinfo.email`
   - `.../auth/userinfo.profile`
   - `.../auth/calendar.readonly`
6. Click "Save and Continue"
7. On the "Test users" page, add your own Google email address (required while the app is in testing mode)
8. Click "Save and Continue", then "Back to Dashboard"

### Create OAuth credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth client ID"
3. Select "Web application" as the application type
4. Give it a name (e.g., "Rails App")
5. Under "Authorized redirect URIs", add:
   - For local development: `http://localhost:3000/users/auth/google_oauth2/callback`
   - For production: `https://your-domain.com/users/auth/google_oauth2/callback`
6. Click "Create"

You'll see a popup with your **Client ID** and **Client Secret**. Save these! You'll need them in the next step.

### Store your credentials

Create a `.env` file in your Rails app root (if you don't have one already) and add:

```
GOOGLE_CLIENT_ID=your_client_id_here
GOOGLE_CLIENT_SECRET=your_client_secret_here
```

**Important**: Make sure `.env` is in your `.gitignore` file so you don't accidentally commit your secrets!

## Step 5: Configure OmniAuth in Devise

Now we need to tell Devise to use Google for authentication. Open `config/initializers/devise.rb` and find the OmniAuth section (around line 271):

```ruby
# config/initializers/devise.rb

  # ==> OmniAuth
  # Add a new OmniAuth provider. Check the wiki for more information on setting
  # up on your models and hooks.
  # config.omniauth :github, 'APP_ID', 'APP_SECRET', scope: 'user,public_repo'
```

Replace the commented-out `config.omniauth` line with:

```ruby
# config/initializers/devise.rb

  # ==> OmniAuth
  # Add a new OmniAuth provider. Check the wiki for more information on setting
  # up on your models and hooks.
  config.omniauth :google_oauth2,
    ENV.fetch("GOOGLE_CLIENT_ID"),
    ENV.fetch("GOOGLE_CLIENT_SECRET"),
    scope: "email,profile,https://www.googleapis.com/auth/calendar.readonly"
```

The `scope` parameter tells Google what permissions we're requesting:
- `email` - access to the user's email address
- `profile` - access to basic profile info (name, profile picture)
- `https://www.googleapis.com/auth/calendar.readonly` - read-only access to calendar events

## Step 6: Add OAuth columns to the users table

We need to store some additional information for users who sign in with Google:

```
bin/rails generate migration AddOmniAuthColumnsToUsers provider:string uid:string google_access_token:string
```

This creates a migration that adds three columns:
- `provider` - stores "google_oauth2" to identify how the user signed up
- `uid` - stores the user's unique Google ID
- `google_access_token` - stores the token we'll use to access their calendar

Run the migration:

```
bin/rails db:migrate
```

## Step 7: Create the OmniAuth callbacks controller

When a user successfully authenticates with Google, Google redirects them back to our app. We need a controller to handle this callback:

Create `app/controllers/omniauth_callbacks_controller.rb`:

```ruby
# app/controllers/omniauth_callbacks_controller.rb

class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      session["devise.google_data"] = request.env["omniauth.auth"].except(:extra)
      redirect_to root_url, alert: "Something went wrong."
    end
  end
end
```

This controller:
1. Receives the OAuth data from Google via `request.env["omniauth.auth"]`
2. Calls `User.from_omniauth` to find or create the user (we'll write this next)
3. Signs them in and redirects to the home page
