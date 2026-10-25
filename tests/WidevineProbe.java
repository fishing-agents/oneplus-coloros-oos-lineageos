import android.media.MediaDrm;
import java.util.UUID;

// Manual Widevine check. Run with: bash tests/run-probe.sh WidevineProbe [serial]
// Prints only security level, provisioning status and HDCP level; never device-unique IDs.
public class WidevineProbe {
    public static void main(String[] args) throws Exception {
        // MediaDrm needs an op package name; bare app_process has none. systemMain() sets "android".
        android.os.Looper.prepare();
        Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
        UUID widevine = new UUID(0xEDEF8BA979D64ACEL, 0xA3C827DCD51D21EDL);
        if (!MediaDrm.isCryptoSchemeSupported(widevine)) {
            System.out.println("WIDEVINE unsupported");
            System.exit(1);
        }
        MediaDrm drm = new MediaDrm(widevine);
        try {
            System.out.println("securityLevel=" + drm.getPropertyString("securityLevel"));
            System.out.println("hdcpLevel=" + drm.getPropertyString("hdcpLevel") + " maxHdcpLevel=" + drm.getPropertyString("maxHdcpLevel"));
            try {
                drm.closeSession(drm.openSession());
                System.out.println("openSession=PASS");
            } catch (Exception e) {
                System.out.println("openSession=FAIL exception=" + e.getClass().getSimpleName());
            }
        } finally {
            drm.close();
        }
    }
}
