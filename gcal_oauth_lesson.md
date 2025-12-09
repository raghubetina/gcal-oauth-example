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
