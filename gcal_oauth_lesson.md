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

**Important**: If you skip this step, you'll get a "Google Calendar API has not been used in project... or it is disabled" error when trying to fetch events. You can also enable it directly at: `https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview`

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
7. On the "Test users" page, click "Add Users" and add your own Google email address

**Important**: While your app is in "Testing" mode, only users you add here can sign in. If you skip this step, you'll see "Access blocked: [App name] has not completed the Google verification process" when trying to sign in.

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
    scope: "email,profile,https://www.googleapis.com/auth/calendar.readonly",
    prompt: "consent",
    access_type: "offline"
```

The options:
- `scope` tells Google what permissions we're requesting:
  - `email` - access to the user's email address
  - `profile` - access to basic profile info (name, profile picture)
  - `https://www.googleapis.com/auth/calendar.readonly` - read-only access to calendar events
- `prompt: "consent"` forces Google to show the consent screen every time, ensuring all scopes are requested (helpful if you change scopes later)
- `access_type: "offline"` tells Google we want a refresh token (for future use)

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

## Step 8: Update the User model

Now we need to add the `:omniauthable` module to Devise and create the `from_omniauth` method:

```ruby
# app/models/user.rb

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid)
    user ||= find_by(email: auth.info.email)
    user ||= new(
      email: auth.info.email,
      password: Devise.friendly_token[0, 20]
    )

    user.provider = auth.provider
    user.uid = auth.uid
    user.google_access_token = auth.credentials.token
    user.save
    user
  end
end
```

Key changes:
- Added `:omniauthable` to the Devise modules
- Added `omniauth_providers: [:google_oauth2]` to specify which providers we support
- The `from_omniauth` class method:
  - First tries to find an existing user by `provider` and `uid` (returning Google user)
  - Falls back to finding by email (in case they signed up with email first)
  - Creates a new user only if neither exists
  - **Always updates** the `google_access_token` on every sign-in (this is important - tokens can change or expire)

## Step 9: Add the Google Calendar API gem

To fetch calendar events, we need Google's official API client:

```ruby
# Gemfile

gem "google-apis-calendar_v3"
```

Then:

```
bundle install
```

This gem provides a Ruby interface to the Google Calendar API.

## Step 10: Create the PagesController

Now let's create a controller that fetches and displays calendar events:

```ruby
# app/controllers/pages_controller.rb

class PagesController < ApplicationController
  before_action :authenticate_user!

  def home
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = current_user.google_access_token

    response = service.list_events(
      "primary",
      max_results: 10,
      single_events: true,
      order_by: "startTime",
      time_min: Time.now.iso8601
    )

    @events = response.items || []
  rescue Google::Apis::ClientError
    sign_out current_user
    redirect_to new_user_session_path,
      alert: "We need permission to access your calendar. Please sign in again."
  end
end
```

This controller:
- Requires the user to be signed in (`before_action :authenticate_user!`)
- Creates a Google Calendar API service
- Uses the user's stored access token for authorization
- Fetches up to 10 upcoming events from their primary calendar
- `"primary"` refers to the user's main calendar
- If the API call fails (expired token, wrong scopes, etc.), it signs the user out and asks them to re-authenticate

## Step 11: Set up routes

Update `config/routes.rb` to wire everything together:

```ruby
# config/routes.rb

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "omniauth_callbacks"
  }

  root "pages#home"
end
```

This does two things:
1. Tells Devise to use our custom `OmniauthCallbacksController` for OAuth callbacks
2. Sets the root route to `pages#home`

## Step 12: Create the home view

Create `app/views/pages/home.html.erb`:

```erb
<%# app/views/pages/home.html.erb %>

<h1>Your Upcoming Events</h1>

<p>Signed in as <%= current_user.email %></p>

<p><%= link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete } %></p>

<% if @events.any? %>
  <ul>
    <% @events.each do |event| %>
      <li>
        <strong><%= event.summary %></strong>
        <br>
        <% if event.start.date_time %>
          <%= event.start.date_time.strftime("%B %d, %Y at %l:%M %p") %>
        <% else %>
          <%= event.start.date %> (all day)
        <% end %>
      </li>
    <% end %>
  </ul>
<% else %>
  <p>No upcoming events found.</p>
<% end %>
```

This view:
- Shows the user's email
- Provides a sign out link
- Loops through `@events` and displays each event's title and start time
- Handles both timed events and all-day events

## Try it out!

1. Make sure your `.env` file has your Google credentials
2. Start the server: `bin/dev`
3. Visit `http://localhost:3000`
4. You'll be redirected to sign in - click "Sign in with Google"
5. Authorize the app to access your calendar
6. You should see your upcoming events!

## Troubleshooting

### "Access blocked: [App name] has not completed the Google verification process"

Your app is in "Testing" mode and you haven't added yourself as a test user. Go to the OAuth consent screen in Google Cloud Console and add your email under "Test users".

### "Google Calendar API has not been used in project... or it is disabled"

You need to enable the Google Calendar API in your Google Cloud project. Go to APIs & Services > Library, search for "Google Calendar API", and click Enable.

### "Request had insufficient authentication scopes"

The access token doesn't have calendar permissions. This can happen if:
1. You didn't add the calendar scope to your OAuth consent screen
2. You signed in before adding the scope, and Google remembered the old permissions

The app handles this automatically by signing you out and asking you to re-authenticate. Make sure the calendar scope is configured in your OAuth consent screen.

### Redirect loop (keeps asking you to sign in)

Check the server logs for the specific error. Common causes:
- Google Calendar API not enabled
- Missing or incorrect scopes
- Token issues

The `rescue Google::Apis::ClientError` in the controller catches these and redirects to sign-in, which can create a loop if the underlying issue isn't fixed.
