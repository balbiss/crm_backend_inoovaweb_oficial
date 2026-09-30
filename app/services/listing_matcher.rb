# Acha o imóvel/condomínio certo a partir do nome que a IA informa, dentro do
# catálogo que aquele canal (inbox) pode ver.
#
# Antes a busca era "qualquer palavra bate" + pegar o primeiro registro — achado
# real (conta DMG Imóveis, canal Santa Cruz): a IA pedia "Alea Santa Cruz", o
# "Alea" batia primeiro com o condomínio "Alea Jaú" e o lead recebia fotos do
# empreendimento de outra cidade (12 vezes em 10 dias), com a IA afirmando que
# eram de Santa Cruz. Agora cada candidato recebe uma pontuação (quantas palavras
# do pedido ele cobre), e só é considerado "achado" quando um único candidato
# cobre TODAS as palavras. Empate ou cobertura parcial não envia nada — devolve
# as opções pra IA confirmar com o cliente.
class ListingMatcher
  # Palavras que aparecem em quase todo pedido/cadastro e não ajudam a
  # diferenciar um empreendimento do outro.
  GENERIC_WORDS = %w[
    de da do das dos di em no na nos nas um uma com para pra por
    foto fotos imagem imagens video videos
    imovel imoveis casa casas apartamento apartamentos apto aptos sobrado sobrados
    condominio condominios residencial residenciais empreendimento empreendimentos
    lancamento lancamentos predio predios edificio unidade unidades
  ].to_set.freeze

  Match = Struct.new(:record, :matched, :matched_in_name, :full, keyword_init: true)
  Result = Struct.new(:status, :record, :options, keyword_init: true) # :found, :ambiguous, :partial, :not_found

  def self.normalize(text)
    ActiveSupport::Inflector.transliterate(text.to_s.downcase)
      .gsub(/(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])/, ' ')
      .gsub(/[^a-z0-9]+/, ' ')
      .strip
  end

  def self.tokens(text)
    normalize(text).split.select { |w| w.match?(/\A\d+\z/) || (w.length >= 3 && !GENERIC_WORDS.include?(w)) }.uniq
  end

  def self.type_key(record)
    record.is_a?(Condominium) ? 'condominio' : 'imovel'
  end

  def self.label(record)
    record.try(:name).presence || record.try(:title).presence || record.try(:property_type).presence || 'Imóvel'
  end

  def self.describe(record)
    "#{label(record).strip} (ID #{record.id}, listing_type '#{type_key(record)}')"
  end

  def initialize(inbox, account_id)
    @inbox = inbox
    @account_id = account_id
  end

  def restricted?
    @inbox.respond_to?(:ai_listing_scope) && @inbox.ai_listing_scope == 'selected'
  end

  def condominiums
    scope = Condominium.where(account_id: @account_id)
    restricted? ? scope.where(id: Array(@inbox.ai_condominium_ids)) : scope
  end

  def properties
    scope = Property.where(account_id: @account_id)
    restricted? && !@inbox.ai_include_properties ? scope.none : scope
  end

  # Ordena os registros pela aderência ao nome pedido; descarta quem não bate
  # nenhuma palavra.
  def rank(records, name)
    toks = self.class.tokens(name)
    return [] if toks.empty?

    records.filter_map do |record|
      name_text = self.class.normalize(name_fields(record))
      location_text = self.class.normalize(location_fields(record))
      in_name = toks.count { |t| token_in?(t, name_text) }
      matched = toks.count { |t| token_in?(t, name_text) || token_in?(t, location_text) }
      next if matched.zero?

      Match.new(record: record, matched: matched, matched_in_name: in_name, full: matched == toks.size)
    end.sort_by { |m| [-m.matched, -m.matched_in_name] }
  end

  def find_by_name(name)
    return Result.new(status: :not_found, options: []) if self.class.tokens(name).empty?

    candidates = condominiums.to_a + properties.limit(500).to_a
    ranked = rank(candidates, name)
    return Result.new(status: :not_found, options: []) if ranked.empty?

    best = ranked.first
    tied = ranked.select { |m| m.matched == best.matched && m.matched_in_name == best.matched_in_name }

    if tied.size > 1
      Result.new(status: :ambiguous, options: tied.map(&:record))
    elsif best.full
      Result.new(status: :found, record: best.record, options: [])
    else
      Result.new(status: :partial, record: best.record, options: ranked.first(5).map(&:record))
    end
  end

  # Busca por ID respeitando o catálogo do canal. Imóveis e condomínios são
  # tabelas separadas, então o mesmo número pode existir nas duas — por isso
  # 'listing_type' desambigua; sem ele, devolve tudo que tiver aquele ID.
  def find_by_id(id, listing_type = nil)
    return [] if id.blank?

    found = []
    found << condominiums.find_by(id: id) unless listing_type == 'imovel'
    found << properties.find_by(id: id) unless listing_type == 'condominio'
    found.compact
  end

  # Lista curta do que o canal pode oferecer, pra IA escolher pelo ID quando o
  # nome não bateu.
  def available_summary(limit = 10)
    items = condominiums.order(:id).limit(limit).to_a
    items += properties.where(status: 'Disponível').order(:id).limit([limit - items.size, 0].max).to_a
    items.map { |r| self.class.describe(r) }
  end

  private

  def name_fields(record)
    [record.try(:name), record.try(:title), record.try(:condo_name)].compact.join(' ')
  end

  def location_fields(record)
    [record.try(:neighborhood), record.try(:city)].compact.join(' ')
  end

  # Números só batem como palavra inteira ("fase 3" não pode bater com "fase
  # 13"); palavras aceitam variação de plural/singular simples ("jardim" x
  # "jardins") e nomes colados no cadastro ("patio" dentro de "casapatio").
  def token_in?(token, text)
    return text.match?(/(?<![0-9])#{token}(?![0-9])/) if token.match?(/\A\d+\z/)
    return true if text.include?(token)
    return true if token.end_with?('s') && token.length > 4 && text.include?(token.chomp('s'))

    token.length >= 5 && text.include?(token[0..-2])
  end
end
