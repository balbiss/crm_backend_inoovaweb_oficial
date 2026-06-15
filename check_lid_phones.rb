Contact.where("length(phone) >= 14 AND phone NOT LIKE '+%'").each do |contact|
  if contact.jid.present? && contact.jid.include?('@lid')
    # Can we fix it? We don't have the real phone. 
    # Just leave it for now, but let's see how many there are.
    puts "Contact #{contact.id} has LID phone: #{contact.phone}"
  end
end
