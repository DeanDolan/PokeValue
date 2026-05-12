require "test_helper"

class RaffleTest < ActiveSupport::TestCase
  test "raffle accepts valid details" do
    host = create_user("rafflehost1")

    raffle = Raffle.new(
      host: host,
      title: "Sealed Booster Box Raffle",
      raffle_kind: "raffle",
      status: "active",
      ticket_price_cents: 500,
      total_tickets: 20,
      revolut_tag: "@rafflehost1"
    )

    assert raffle.valid?
  end

  test "raffle rejects missing required details" do
    raffle = Raffle.new(
      title: nil,
      raffle_kind: nil,
      status: nil,
      ticket_price_cents: nil,
      total_tickets: nil,
      revolut_tag: nil
    )

    assert_not raffle.valid?
    assert raffle.errors[:title].any?
    assert raffle.errors[:raffle_kind].any?
    assert raffle.errors[:status].any?
    assert raffle.errors[:ticket_price_cents].any?
    assert raffle.errors[:total_tickets].any?
    assert raffle.errors[:revolut_tag].any?
  end

  test "raffle ticket accepts valid details" do
    host = create_user("rafflehost2")
    user = create_user("raffleuser1")

    raffle = Raffle.create!(
      host: host,
      title: "Elite Trainer Box Raffle",
      raffle_kind: "raffle",
      status: "active",
      ticket_price_cents: 500,
      total_tickets: 20,
      revolut_tag: "@rafflehost2"
    )

    ticket = RaffleTicket.new(
      raffle: raffle,
      user: user,
      ticket_number: 1,
      amount_paid_cents: 500,
      revolut_tag: "@raffleuser1",
      paid: true,
      verified: false
    )

    assert ticket.valid?
  end

  private

  def create_user(username)
    User.create!(
      username: username,
      country_code: "IE",
      revolut_tag: "@#{username}",
      password: "StrongPass1!",
      password_confirmation: "StrongPass1!"
    )
  end
end
