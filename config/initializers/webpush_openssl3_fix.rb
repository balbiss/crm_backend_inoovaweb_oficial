# A gem "webpush" (ultima versao publicada em 2020) usa uma forma de gerar
# chave EC efemera que quebra no OpenSSL 3.0 ("pkeys are immutable").
# Corrige so a geracao da chave, mantendo o resto do metodo original identico.
Rails.application.config.to_prepare do
  module Webpush
    module Encryption
      def encrypt(message, p256dh, auth)
        assert_arguments(message, p256dh, auth)

        group_name = 'prime256v1'
        salt = Random.new.bytes(16)

        server = OpenSSL::PKey.generate_key('EC', ec_paramgen_curve: group_name, ec_param_enc: 'named_curve')
        server_public_key_bn = server.public_key.to_bn

        group = OpenSSL::PKey::EC::Group.new(group_name)
        client_public_key_bn = OpenSSL::BN.new(Webpush.decode64(p256dh), 2)
        client_public_key = OpenSSL::PKey::EC::Point.new(group, client_public_key_bn)

        shared_secret = server.dh_compute_key(client_public_key)

        client_auth_token = Webpush.decode64(auth)

        info = "WebPush: info\0" + client_public_key_bn.to_s(2) + server_public_key_bn.to_s(2)
        content_encryption_key_info = "Content-Encoding: aes128gcm\0"
        nonce_info = "Content-Encoding: nonce\0"

        prk = HKDF.new(shared_secret, salt: client_auth_token, algorithm: 'SHA256', info: info).next_bytes(32)
        content_encryption_key = HKDF.new(prk, salt: salt, info: content_encryption_key_info).next_bytes(16)
        nonce = HKDF.new(prk, salt: salt, info: nonce_info).next_bytes(12)

        ciphertext = encrypt_payload(message, content_encryption_key, nonce)

        serverkey16bn = convert16bit(server_public_key_bn)
        rs = ciphertext.bytesize
        raise ArgumentError, "encrypted payload is too big" if rs > 4096

        aes128gcmheader = "#{salt}" + [rs].pack('N*') + [serverkey16bn.bytesize].pack('C*') + serverkey16bn

        aes128gcmheader + ciphertext
      end
    end

    # Mesmo problema em VapidKey: initialize e os setters public_key=/private_key=
    # mutavam um OpenSSL::PKey::EC ja existente, o que o OpenSSL 3.0 nao permite mais.
    # Reconstroi a chave via DER (SEC1 ECPrivateKey) sempre que os dois valores
    # (publico + privado) estiverem disponiveis, ao inves de mutar um pkey existente.
    class VapidKey
      def initialize
        @curve = OpenSSL::PKey.generate_key('EC', ec_paramgen_curve: 'prime256v1', ec_param_enc: 'named_curve')
      end

      def public_key=(key)
        @public_key_bn = to_big_num(key)
        rebuild_curve
      end

      def private_key=(key)
        @private_key_bn = to_big_num(key)
        rebuild_curve
      end

      private

      def rebuild_curve
        return unless @public_key_bn && @private_key_bn

        group = OpenSSL::PKey::EC::Group.new('prime256v1')
        point = OpenSSL::PKey::EC::Point.new(group, @public_key_bn)
        asn1 = OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(1),
          OpenSSL::ASN1::OctetString(@private_key_bn.to_s(2)),
          OpenSSL::ASN1::ASN1Data.new([OpenSSL::ASN1::ObjectId('prime256v1')], 0, :CONTEXT_SPECIFIC),
          OpenSSL::ASN1::ASN1Data.new([OpenSSL::ASN1::BitString(point.to_octet_string(:uncompressed))], 1, :CONTEXT_SPECIFIC)
        ])
        @curve = OpenSSL::PKey::EC.new(asn1.to_der)
      end
    end
  end
end
