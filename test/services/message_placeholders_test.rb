require "test_helper"

class MessagePlaceholdersTest < ActiveSupport::TestCase
  FakeContact = Struct.new(:name)

  test "troca [Nome] pelo primeiro nome do contato" do
    assert_equal "Oi Brenda! Tudo bem? 😊", MessagePlaceholders.fill("Oi [Nome]! Tudo bem? 😊", FakeContact.new("Brenda V.💋"))
    assert_equal "Wesley, já tenho tudo que preciso 🏡", MessagePlaceholders.fill("[nome], já tenho tudo que preciso 🏡", FakeContact.new("wesley"))
    assert_equal "Perfeito, Ana!", MessagePlaceholders.fill("Perfeito, {{nome}}!", FakeContact.new("Ana Souza"))
  end

  test "remove o marcador quando o nome do WhatsApp não é um nome" do
    assert_equal "Oi! Tudo bem?", MessagePlaceholders.fill("Oi [Nome]! Tudo bem?", FakeContact.new("anacisantos257"))
    assert_equal "Já tenho tudo que preciso", MessagePlaceholders.fill("[Nome], já tenho tudo que preciso", FakeContact.new(nil))
  end

  test "não mexe em texto sem marcador" do
    text = "Oi! Posso te mandar as fotos [do Alea]?"
    assert_same text, MessagePlaceholders.fill(text, FakeContact.new("Ana"))
  end
end
