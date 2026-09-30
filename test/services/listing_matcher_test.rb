require "test_helper"

class ListingMatcherTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:one)
    @inbox = Inbox.create!(account: @account, name: "Santa Cruz", provider: "baileys")
    # Espelha o cadastro real da conta DMG Imóveis.
    @jau = Condominium.create!(account: @account, name: "Alea Jaú", neighborhood: "Centro", city: "Jaú")
    @santa_cruz = Condominium.create!(account: @account, name: "Alea Santa cruz CASAPATIO FASE 3", neighborhood: "JARDIM MARIA LUIZA", city: "SANTA CRUZ DO RIO PARDO")
    @orlandia = Condominium.create!(account: @account, name: "Alea Orlândia ", neighborhood: "Centro", city: "Orlândia")
    @sertaozinho = Condominium.create!(account: @account, name: "SERTÃOZINHO ", neighborhood: "Centro", city: "Sertãozinho")
  end

  def matcher
    ListingMatcher.new(@inbox, @account.id)
  end

  test "nome completo acha o empreendimento certo mesmo com outro Alea cadastrado antes" do
    result = matcher.find_by_name("Alea Santa Cruz")
    assert_equal :found, result.status
    assert_equal @santa_cruz, result.record
  end

  test "acha pela cidade/bairro e por nome colado no cadastro" do
    assert_equal @santa_cruz, matcher.find_by_name("casas na Maria Luiza").record
    assert_equal @santa_cruz, matcher.find_by_name("Casa Pátio fase 3").record
    assert_equal @orlandia, matcher.find_by_name("Alea Orlandia").record
    assert_equal @jau, matcher.find_by_name("fotos do Alea Jau").record
  end

  test "nome que bate em vários com o mesmo peso é ambíguo, não chuta" do
    result = matcher.find_by_name("Alea")
    assert_equal :ambiguous, result.status
    assert_nil result.record
    assert_equal 3, result.options.size
  end

  test "fase diferente da cadastrada não conta como achado" do
    result = matcher.find_by_name("Casa Pátio Fase 1")
    assert_equal :partial, result.status
    assert_equal @santa_cruz, result.record
  end

  test "número só bate como palavra inteira" do
    Condominium.create!(account: @account, name: "Casa Pátio Fase 13", city: "Bauru")
    result = matcher.find_by_name("Casa Pátio Fase 3")
    assert_equal :found, result.status
    assert_equal @santa_cruz, result.record
  end

  test "canal restrito só enxerga os empreendimentos marcados" do
    @inbox.update!(ai_listing_scope: "selected", ai_condominium_ids: [@santa_cruz.id])

    assert_equal [@santa_cruz], matcher.condominiums.to_a
    assert_equal :found, matcher.find_by_name("Alea").status
    # Jaú não está liberado neste canal: o Alea que sobrou só bate parcialmente.
    assert_equal :partial, matcher.find_by_name("Alea Jaú").status
    assert_equal [], matcher.find_by_id(@jau.id)
    assert_equal [@santa_cruz], matcher.find_by_id(@santa_cruz.id)
  end

  test "canal restrito sem nada marcado não enxerga nada" do
    @inbox.update!(ai_listing_scope: "selected", ai_condominium_ids: [], ai_include_properties: false)
    Property.create!(account: @account, title: "Casa Centro", status: "Disponível")

    assert_empty matcher.condominiums
    assert_empty matcher.properties
    assert_equal :not_found, matcher.find_by_name("Alea Santa Cruz").status
  end

  test "find_by_id diferencia imóvel avulso de condomínio com o mesmo número" do
    condo = @sertaozinho
    prop = Property.create!(id: condo.id, account: @account, title: "Apto Centro", status: "Disponível")

    assert_equal [condo], matcher.find_by_id(prop.id, "condominio")
    assert_equal [prop], matcher.find_by_id(prop.id, "imovel")
    assert_equal 2, matcher.find_by_id(prop.id).size
  end
end
