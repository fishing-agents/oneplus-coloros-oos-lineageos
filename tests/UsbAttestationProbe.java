import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyProperties;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.spec.ECGenParameterSpec;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

// Manual Android 12+ AndroidKeyStore test. Run with: bash tests/run-probe.sh UsbAttestationProbe [serial]
// Creates/deletes only its own test keys; never prints certificates or device identifiers.
public class UsbAttestationProbe {
    public static void main(String[] args) throws Exception {
        Class.forName("android.security.keystore2.AndroidKeyStoreProvider").getMethod("install").invoke(null);
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        String prefix = "pi_usb_probe_" + UUID.randomUUID();
        System.out.println("probe_uid=" + android.os.Process.myUid());
        boolean passed = true;
        for (boolean attest : new boolean[]{false, true}) {
            String alias = prefix + "_" + attest;
            String label = attest ? "DEFAULT_ATTESTATION" : "PLAIN_EC";
            try {
                KeyGenParameterSpec.Builder spec = new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256);
                if (attest) spec.setAttestationChallenge(new byte[]{1, 2, 3, 4});
                KeyPairGenerator generator = KeyPairGenerator.getInstance("EC", "AndroidKeyStore");
                generator.initialize(spec.build());
                KeyPair pair = generator.generateKeyPair();
                KeyInfo info = KeyFactory.getInstance("EC", "AndroidKeyStore").getKeySpec(pair.getPrivate(), KeyInfo.class);
                Certificate[] chain = store.getCertificateChain(alias);
                if (chain == null || chain.length == 0) throw new IllegalStateException();
                for (int i = 0; i + 1 < chain.length; i++) chain[i].verify(chain[i + 1].getPublicKey());
                boolean extension = ((java.security.cert.X509Certificate) chain[0]).getExtensionValue("1.3.6.1.4.1.11129.2.1.17") != null;
                if (attest && !extension) throw new IllegalStateException("Missing attestation extension");
                System.out.println(label + " PASS security_level=" + info.getSecurityLevel() + " chain_length=" + chain.length + " attestation_extension=" + extension + " chain_signatures_valid=true");
            } catch (Exception error) {
                passed = false;
                System.out.println(label + " FAIL exception=" + error.getClass().getSimpleName());
                for (Throwable cause = error; cause != null; cause = cause.getCause()) {
                    String message = String.valueOf(cause.getMessage());
                    Matcher matcher = Pattern.compile("internal Keystore code:\\s*(-?\\d+)").matcher(message);
                    if (matcher.find()) System.out.println(label + " internal_keystore_code=" + matcher.group(1));
                    if (cause.getClass().getName().equals("android.security.KeyStoreException")) {
                        try { System.out.println(label + " public_keystore_code=" + cause.getClass().getMethod("getNumericErrorCode").invoke(cause)); }
                        catch (ReflectiveOperationException ignored) { System.out.println(label + " public_keystore_code=unavailable"); }
                    }
                    for (String token : new String[]{"SECURE_HW_COMMUNICATION_FAILED", "ATTESTATION_KEYS_NOT_PROVISIONED", "ATTESTATION_IDS_NOT_PROVISIONED", "KEYMINT_NOT_CONFIGURED", "ATTESTATION_APPLICATION_ID_MISSING", "CANNOT_ATTEST_IDS"}) {
                        if (message.contains(token)) System.out.println(label + " native_error=" + token);
                    }
                }
            } finally {
                store.deleteEntry(alias);
                System.out.println(label + " test_key_deleted=true");
            }
        }
        System.out.println("RESULT=" + (passed ? "PASS" : "FAIL"));
        if (!passed) System.exit(1);
    }
}
