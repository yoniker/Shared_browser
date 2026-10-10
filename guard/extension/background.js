// Signs the shared browser out of Google once a GTO Genesis login finishes.
//
// GTO Genesis only offers "Continue with Google". After the OAuth round trip the
// GTO session no longer needs Google's cookies, but leaving them in place would
// let whoever has control open Gmail, Drive or your Google Account as you.

const GOOGLE_COOKIE_DOMAIN = /(^|\.)(google\.[a-z]{2,3}(\.[a-z]{2})?|youtube\.com)$/;
const SIGN_OUT_DELAY_MS = 3000;

async function signOutOfGoogle() {
  // Partitioned (CHIPS) cookies are only returned when a partitionKey is given.
  const lists = await Promise.all([
    chrome.cookies.getAll({}),
    chrome.cookies.getAll({ partitionKey: {} }),
  ]);
  const google = lists.flat().filter((c) => GOOGLE_COOKIE_DOMAIN.test(c.domain));
  await Promise.all(
    google.map((c) =>
      chrome.cookies.remove({
        url: `http${c.secure ? "s" : ""}://${c.domain.replace(/^\./, "")}${c.path}`,
        name: c.name,
        storeId: c.storeId,
        ...(c.partitionKey && { partitionKey: c.partitionKey }),
      }),
    ),
  );
}

// GTO Genesis logs in through Supabase: Google hands the result to
// <project>.supabase.co/auth/v1/callback, which redirects back to the app.
// That request only happens once Google sign-in has completed.
chrome.webRequest.onBeforeRequest.addListener(
  () => {
    setTimeout(signOutOfGoogle, SIGN_OUT_DELAY_MS);
  },
  { urls: ["https://*.supabase.co/auth/v1/callback*"], types: ["main_frame"] },
);
