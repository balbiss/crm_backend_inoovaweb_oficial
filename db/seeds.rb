# Clear existing data
Message.destroy_all
Conversation.destroy_all
Contact.destroy_all
User.destroy_all
Account.destroy_all

# Create Account
account = Account.create!(name: 'Innovaweb CRM')

# Create User
user = User.create!(
  account: account,
  email: 'balbis2050@gmail.com',
  password: '280896Ab@',
  password_confirmation: '280896Ab@',
  first_name: 'Guilherme',
  last_name: 'Balbis',
  role: :admin
)

# Create Contacts
contact1 = Contact.create!(
  account: account,
  name: 'Renato Lima',
  email: 'renato@example.com',
  phone: '+55 11 99999-9999'
)

contact2 = Contact.create!(
  account: account,
  name: 'João Pedro',
  email: 'joao@example.com',
  phone: '+55 21 98888-8888'
)

# Create Conversations
conv1 = Conversation.create!(
  account: account,
  contact: contact1,
  user: user,
  status: :open,
  source: 'whatsapp',
  unread_count: 2
)

conv2 = Conversation.create!(
  account: account,
  contact: contact2,
  user: user,
  status: :open,
  source: 'instagram',
  unread_count: 0
)

# Create Messages
Message.create!(
  account: account,
  conversation: conv1,
  sender_type: 'Contact',
  sender_id: contact1.id,
  text: 'Olá, boa noite!',
  status: :read,
  created_at: 1.hour.ago
)

Message.create!(
  account: account,
  conversation: conv1,
  sender_type: 'User',
  sender_id: user.id,
  text: 'Boa noite Renato, como posso ajudar?',
  status: :read,
  created_at: 55.minutes.ago
)

Message.create!(
  account: account,
  conversation: conv1,
  sender_type: 'Contact',
  sender_id: contact1.id,
  text: 'Eu acho que você não deveria ter feito isso com a minha conta ontem. Tive muitos problemas.',
  status: :read,
  created_at: 10.minutes.ago
)

Message.create!(
  account: account,
  conversation: conv2,
  sender_type: 'Contact',
  sender_id: contact2.id,
  text: 'Pode me enviar o catálogo atualizado?',
  status: :read,
  created_at: 1.day.ago
)

puts "Database seeded successfully!"
