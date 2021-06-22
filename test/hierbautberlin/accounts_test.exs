defmodule Hierbautberlin.AccountsTest do
  use Hierbautberlin.DataCase

  alias Hierbautberlin.Accounts
  alias Hierbautberlin.Repo
  alias Hierbautberlin.Accounts.{User, UserToken, Subscription}

  import Hierbautberlin.AccountsFixtures

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_user(%{email: "invalid", password: "invalid"})

      assert %{
               email: ["muss ein @-Zeichen und keine Leerzeichen haben"],
               password: ["should be at least 8 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 80 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} = Accounts.apply_user_email(user, valid_user_password(), %{})
      assert %{email: ["hat sich nicht geändert"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: "not valid"})

      assert %{email: ["muss ein @-Zeichen und keine Leerzeichen haben"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["ist ungültig"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()
      {:ok, user} = Accounts.apply_user_email(user, valid_user_password(), %{email: email})
      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert Accounts.update_user_email(user, token) == :ok
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at != user.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "invalid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 8 character(s)"],
               password_confirmation: ["stimmt nicht mit dem Passwort überein"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: too_long})

      assert "should be at most 80 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{password: valid_user_password()})

      assert %{current_password: ["ist ungültig"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "invalid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 8 character(s)"],
               password_confirmation: ["stimmt nicht mit dem Passwort überein"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 80 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "change_role/2" do
    setup do
      %{user: user_fixture()}
    end

    test "updates the role", %{user: user} do
      {:ok, _user} = Accounts.change_role(user, :admin)
      assert Accounts.get_user!(user.id).role == :admin
    end

    test "refutes update if role is not in enum", %{user: user} do
      {:error, changeset} = Accounts.change_role(user, :wrong)
      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "subscribe/2" do
    setup do
      %{user: user_fixture()}
    end

    test "subscribes to a lat/lng position and use the default radius", %{user: user} do
      {:ok, _subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648})

      user = user |> Repo.preload(:subscriptions)

      assert length(user.subscriptions) == 1

      subscription = List.first(user.subscriptions)
      assert subscription.point.coordinates == {52.52329675804731, 13.445322017049648}
      assert subscription.radius == 2000
    end

    test "subscribes to a lat/lng position and set the radius", %{user: user} do
      {:ok, _subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      user = user |> Repo.preload(:subscriptions)

      assert length(user.subscriptions) == 1

      subscription = List.first(user.subscriptions)
      assert subscription.point.coordinates == {52.52329675804731, 13.445322017049648}
      assert subscription.radius == 4000
    end
  end

  describe "get_subscription/2" do
    setup do
      user = user_fixture()

      {:ok, _subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      %{user: user}
    end

    test "get the current subscription", %{user: user} do
      subscription =
        Accounts.get_subscription(user, %{lat: 52.523296758047, lng: 13.4453220170496})

      assert subscription.point.coordinates == {52.52329675804731, 13.445322017049648}
      assert subscription.radius == 4000
    end

    test "does not return the current subscription of other users" do
      user = user_fixture()

      subscription =
        Accounts.get_subscription(user, %{lat: 52.52329675804731, lng: 13.445322017049648})

      assert subscription == nil
    end

    test "return nil if there is no subscription near that point", %{user: user} do
      subscription = Accounts.get_subscription(user, %{lat: 50.528, lng: 10.449})

      assert subscription == nil
    end
  end

  describe "unsubscribe/2" do
    setup do
      user = user_fixture()

      {:ok, _subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      %{user: user}
    end

    test "unsubscribe a user", %{user: user} do
      {:ok, _subscription} =
        Accounts.unsubscribe(user, %{
          lat: 52.52329675804731,
          lng: 13.445322017049648
        })

      user = user |> Repo.preload(:subscriptions)
      assert Enum.empty?(user.subscriptions)
    end

    test "should not unsubscribe wrong user", %{user: user} do
      other_user = user_fixture()

      {:error, :not_found} =
        Accounts.unsubscribe(other_user, %{
          lat: 52.52329675804731,
          lng: 13.445322017049648
        })

      user = user |> Repo.preload(:subscriptions)
      assert length(user.subscriptions) == 1
    end
  end

  describe "is_subscribed" do
    setup do
      user = user_fixture()

      {:ok, _subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      %{user: user}
    end

    test "returns true if the user is subscribed", %{user: user} do
      assert Accounts.get_subscription(user, %{lat: 52.523296758047, lng: 13.4453220170496})
    end

    test "returns false if the user is not subscribed" do
      user = user_fixture()
      refute Accounts.get_subscription(user, %{lat: 52.523296758047, lng: 13.4453220170496})
    end
  end

  describe "change_subscription/3" do
    setup do
      user = user_fixture()
      %{user: user}
    end

    test "returns a changeset", %{user: user} do
      assert %Ecto.Changeset{} = changeset = Accounts.change_subscription(%Subscription{}, user)
      assert changeset.required == []
    end

    test "allows fields to be set", %{user: user} do
      changeset =
        Accounts.change_subscription(%Subscription{}, user, %{
          lat: 50,
          lng: 12,
          radius: 1234
        })

      assert changeset.valid?
      assert get_change(changeset, :lat) == 50
      assert get_change(changeset, :lng) == 12
      assert get_change(changeset, :radius) == 1234

      assert get_change(changeset, :point) == %Geo.Point{
               coordinates: {50, 12},
               properties: %{},
               srid: 4326
             }
    end
  end

  describe "get_subscription_by_id/2" do
    setup do
      user = user_fixture()

      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      %{user: user, subscription: subscription}
    end

    test "returns a subscription if the user is correct", %{
      user: user,
      subscription: subscription
    } do
      found_subscription = Accounts.get_subscription_by_id(user, subscription.id)
      assert subscription.id == found_subscription.id
    end

    test "returns an error if the user is wrong", %{
      subscription: subscription
    } do
      user = user_fixture()
      assert Accounts.get_subscription_by_id(user, subscription.id) == nil
    end

    test "returns an error if the id does not exist", %{
      user: user
    } do
      assert Accounts.get_subscription_by_id(user, 1_212_121_211_212) == nil
    end
  end

  describe "update_subscription/2" do
    setup do
      user = user_fixture()

      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      %{user: user, subscription: subscription}
    end

    test "updates a subscription", %{user: user, subscription: subscription} do
      {:ok, _sub} = Accounts.update_subscription(subscription, %{lat: 50, lng: 12, radius: 1000})

      sub = Accounts.get_subscription_by_id(user, subscription.id)

      assert sub.point == %Geo.Point{
               coordinates: {50, 12},
               properties: %{},
               srid: 4326
             }

      assert sub.radius == 1000
      assert sub.user_id == user.id
    end
  end

  describe "delete_subscription/1" do
    setup do
      user = user_fixture()

      {:ok, subscription} =
        Accounts.subscribe(user, %{lat: 52.52329675804731, lng: 13.445322017049648, radius: 4000})

      %{user: user, subscription: subscription}
    end

    test "it removes the subscription", %{user: user, subscription: subscription} do
      {:ok, _sub} = Accounts.delete_subscription(subscription)
      assert Accounts.get_subscription_by_id(user, subscription.id) == nil
    end
  end
end
