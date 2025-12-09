
Isn't it nice when an app gives you a few options to make an account? For example, on Render:

![Render example sign in](/assets/render-example.png)

Here, we'll see how to get GitHub [OAuth](https://en.wikipedia.org/wiki/OAuth) implemented in your Rails app!

This guide assumes that you have already implemented Devise in your app, and that you have sign-in/sign-out user accounts. See our [Devise lesson](https://learn.firstdraft.com/lessons/238-authentication-with-devise-basics) for a refresher on setting that up if haven't done so.

Once you have Devise setup, let's get started with adding the ability to sign-up and sign-in with a user's GitHub account!

## Basic configuration

First, add the required gems to your `Gemfile`:

```rb
# Gemfile

gem "omniauth-github"
gem "omniauth-rails_csrf_protection"
```

and:

```
bundle install
```

Then, in your `config/initializers/devise.rb` file, find these lines:

```rb{6(3:)}
# config/initializers/devise.rb

  # ==> OmniAuth
  # Add a new OmniAuth provider. Check the wiki for more information on setting
  # up on your models and hooks.
  # config.omniauth :github, 'APP_ID', 'APP_SECRET', scope: 'user,public_repo'
```

and replace the `config.omniauth` commented-out line with:

```rb{6(3:)}
# config/initializers/devise.rb

  # ==> OmniAuth
  # Add a new OmniAuth provider. Check the wiki for more information on setting
  # up on your models and hooks.
  config.omniauth :github, ENV.fetch("GITHUB_ID"), ENV.fetch("GITHUB_SECRET"), scope: "user"
```

<aside>

For more scopes, [see the documentation from GitHub](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps#available-scopes)
</aside>

## Register an OAuth app on GitHub

You will need to register your application with GitHub to get the two required `ENV` variables above.

Visit [github.com/settings/developers](https://github.com/settings/developers), and then the "OAuth" tab, and click on "Register a new application" (or, if you have already registered one, you will see "New OAuth App" in the upper right corner):

![GitHub register new OAuth app](/assets/register-new-oauth-1.png)
{: .bleed-full }

On the next screen, fill in:

- the "Application name",
- the "Homepage URL"
- and the "Authorization callback URL"

Like so:

![GitHub fill in registration for new OAuth app](/assets/register-new-oauth-2.png)


<div class="alert alert-primary bleed-full">

**Note:** 

If you are working in development in a codespace on your application, you can enter:

```
https://<your-live-application-preview-url>
``` 

(replaced with the live application preview's URL; _not_ your codespace's) in the "Homepage URL", and: 

```
https://<your-live-application-preview-url>/users/auth/github/callback
```

in the "Authorization callback URL".

And if you are working in local development (i.e. not in a codespace browser but directly in VSCode on your laptop), you can enter `http://localhost:3000` in the "Homepage URL", and `http://localhost:3000/users/auth/github/callback` in the "Authorization callback URL".

Later, when you deploy the application, you can change the domain to your deployed name.

</div>


Once you've done that, click on "Register application".

On the next screen, you will see the "Client ID", which is what you need to add for the environment variable `ENV.fetch("GITHUB_ID")` in your app (See [Storing credentials securely](https://learn.firstdraft.com/lessons/52-storing-credentials-securely)). You will also need to click to "Generate a new client secret", which will provide you with the `ENV.fetch("GITHUB_SECRET")` required variable.

![New Client ID and Client secret](/assets/register-new-oauth-3.png)
{: .bleed-full }

_Be sure to save the "Client secret" as `GITHUB_SECRET` in you `.env` file, or somewhere safe, as you won't be able to view it again! See [Storing credentials securely](https://learn.firstdraft.com/lessons/52-storing-credentials-securely)._

Once you have those two environment variables, click "Update application" at the bottom of the page. Now we're ready to return to our application and continue the setup!

## Database migration

Now let's generate a database migration to add GitHub credentials to our users:

```
rails generate migration AddOmniauthAndGithubAccessTokenToUsers
```

And fill the new migration file in with:

```rb
class AddOmniauthAndGithubAccessTokenToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :github_access_token, :string
    add_column :users, :provider, :string
    add_column :users, :uid, :string
  end
end
```

Don't forget to `rails db:migrate` after you add that migration file.

## New route and controller for OAuth

We'll need to setup a new route as well to handle the OAuth flow:

```rb{6-8}
# config/routes.rb

Rails.application.routes.draw do
  # ...

  devise_for :users, controllers: {
    omniauth_callbacks: "omniauth_callbacks",
  }

  # ...
end
```

And we need to create that controller and fill it with this:

```rb
# app/controllers/omniauth_callbacks_controller.rb

class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    @user = User.from_omniauth(request.env["omniauth.auth"].except!(:extra))

    if @user.persisted?
      sign_in_and_redirect @user
      set_flash_message(:notice, :success, kind: "GitHub") if is_navigational_format?
    else
      session["devise.github_data"] = request.env["omniauth.auth"].except!(:extra)
      redirect_to root_url, alert: "Something went wrong."
    end
  end
end
```

## Updates to User model

Finally, we need to update and add a few things in our User model:

```rb{8(5:),12-18}
# app/models/user.rb

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable,
    :omniauthable, omniauth_providers: %i[github]

  # ...

  def self.from_omniauth(auth)
    find_or_create_by(provider: auth.provider, uid: auth.uid) do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.github_access_token = auth.credentials.token
    end
  end
end
```

## New sign-up/sign-in flow

Now, fire up your server and visit `/users/sign_in`. You should see a new "Sign in with GitHub" button:

![New login screen](/assets/new-login-screen.png)

It's not the prettiest thing, but it works! Give it a click and see. The first time you click on it, you will be brought to a confirmation page:

![First time sign in OAuth screen](/assets/first-time-sign-in-oauth-screen.png)

This is essentially a _sign-up_ route! Devise and GitHub will handle creating a new user (or updating an existing one) with the `self.from_omniauth` class method that you added to your User model!

In the future, assuming you are signed in to GitHub in your current browser, when you click the "Sign in with GitHub" button you won't need to confirm anything, since you've already added your credentials the first time.

## Modify your forms

If you would like to modify the sign-in look, let's be sure we have access to the Devise forms:

```
rails generate devise:views -b form_for
```

If you already have access to these forms (e.g. because you [modified them to add additional fields](https://learn.firstdraft.com/lessons/238-authentication-with-devise-basics#customizing-devise-views)), then you don't need to run that generate command.

Now, feel free to tweak the sign-in form (`app/views/devise/sessions/new.html.erb`) to your heart's content!
  