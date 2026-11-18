import javax.crypto.*;
import javax.crypto.spec.*;
import java.util.Base64;
import java.io.InputStreamReader;
import java.io.BufferedReader;

public class WebtopPassEncode {

    public static void main(String args[]) throws Exception {
        String p;
        try {
            p = args[0];
        } catch (ArrayIndexOutOfBoundsException e1) {
            BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
            p = br.readLine();
        } 
        String c=cipher(p,"password");
        System.out.println(c);
    }

    public static String cipher(String pass, String key) throws Exception {
        DESKeySpec ks=new DESKeySpec(key.getBytes("UTF-8"));
        SecretKey sk=SecretKeyFactory.getInstance("DES").generateSecret(ks);
        Cipher cipher=Cipher.getInstance("DES");
        cipher.init(Cipher.ENCRYPT_MODE,sk);
        // MIME encoder with "\n" matches the output of the removed sun.misc.BASE64Encoder
        return Base64.getMimeEncoder(76, new byte[]{'\n'}).encodeToString(cipher.doFinal(pass.getBytes("UTF-8")));
    }

}
