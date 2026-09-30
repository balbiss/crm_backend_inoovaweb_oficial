# Prompts de conta costumam trazer modelos de mensagem com "[Nome]" pra IA
# preencher — e às vezes ela copia o modelo literalmente. Achado real (conta
# DMG Imóveis, conversa #6541): o resgate automático mandou "Oi [Nome]! 😊"
# quatro vezes pro mesmo lead. Troca o marcador pelo primeiro nome do contato,
# ou remove quando o nome do WhatsApp não parece um nome de verdade
# (ex: "anacisantos257", "Brenda V.💋" -> usa só "Brenda").
module MessagePlaceholders
  PLACEHOLDER = /(,?[ \t]*)(?:\[\s*nome(?:\s+do\s+(?:cliente|lead))?\s*\]|\{\{?\s*nome(?:\s+do\s+(?:cliente|lead))?\s*\}?\})/i

  def self.first_name(contact)
    word = contact&.name.to_s.strip.split(/\s+/).first.to_s
    word.match?(/\A[[:alpha:]]{2,}\z/) ? word.capitalize : nil
  end

  def self.fill(text, contact)
    return text if text.blank? || !text.match?(PLACEHOLDER)

    name = first_name(contact)
    result = text.gsub(PLACEHOLDER) { name ? "#{Regexp.last_match(1)}#{name}" : '' }
    return result if name

    # Sem nome: "[Nome], já tenho tudo" virava ", já tenho tudo".
    result = result.sub(/\A[\s,]+/, '')
    result[0] = result[0].upcase if result.present?
    result
  end
end
