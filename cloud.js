(() => {
  const config = window.PUNDITS_SUPABASE;
  const hasSupabase = Boolean(config?.url && config?.anonKey && window.supabase);
  const client = hasSupabase ? window.supabase.createClient(config.url, config.anonKey) : null;

  function isReady() {
    return Boolean(client);
  }

  async function getUser() {
    if (!client) return null;
    const { data } = await client.auth.getUser();
    return data.user || null;
  }

  async function getSession() {
    if (!client) return null;
    const { data } = await client.auth.getSession();
    return data.session || null;
  }

  async function waitForSession(timeoutMs = 6000) {
    if (!client) return null;
    const existing = await getSession();
    if (existing) return existing;

    return new Promise(resolve => {
      let settled = false;
      let subscription;
      const timer = window.setTimeout(() => finish(null), timeoutMs);
      const finish = session => {
        if (settled) return;
        settled = true;
        subscription?.unsubscribe();
        window.clearTimeout(timer);
        resolve(session || null);
      };
      const { data } = client.auth.onAuthStateChange((_event, session) => finish(session));
      subscription = data.subscription;
    });
  }

  async function signIn(email) {
    if (!client) return { ok: false, message: "Supabase is not configured yet." };
    const cleanRedirect = `${window.location.origin}${window.location.pathname}`;
    const { error } = await client.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: cleanRedirect }
    });
    if (!error) return { ok: true, message: "Check your email for the login link." };
    const isRateLimit = error.message.toLowerCase().includes("rate limit");
    return {
      ok: false,
      message: isRateLimit
        ? "Too many login emails were sent. Wait a few minutes, then try again."
        : error.message
    };
  }

  async function signOut() {
    if (!client) return { ok: false, message: "Supabase is not configured yet." };
    const { error } = await client.auth.signOut();
    return error ? { ok: false, message: error.message } : { ok: true };
  }

  async function saveProfile({ email, squadName }) {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Sign in before saving online." };

    const { error } = await client.from("profiles").upsert({
      id: user.id,
      email,
      squad_name: squadName
    });
    return error ? { ok: false, message: error.message } : { ok: true };
  }

  async function ensureProfile(profile = {}) {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Sign in first." };

    const { data: existing, error: existingError } = await client
      .from("profiles")
      .select("id,email,squad_name")
      .eq("id", user.id)
      .maybeSingle();
    if (existingError) return { ok: false, message: existingError.message };
    if (existing) return { ok: true, profile: existing };

    const email = profile.email || user.email || "";
    const squadName = profile.squadName || email.split("@")[0] || "New Pundit";
    const { data, error } = await client.from("profiles").insert({
      id: user.id,
      email,
      squad_name: squadName
    }).select().single();
    return error ? { ok: false, message: error.message } : { ok: true, profile: data };
  }

  async function getProfile() {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Not signed in." };
    const { data, error } = await client.from("profiles").select("*").eq("id", user.id).maybeSingle();
    return error ? { ok: false, message: error.message } : { ok: true, profile: data };
  }

  async function createLeague(name) {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Sign in before creating a league." };
    const profile = await ensureProfile();
    if (!profile.ok) return profile;

    const code = `WC26-${Math.floor(1000 + Math.random() * 9000)}`;
    const { data, error } = await client.from("leagues").insert({
      name,
      code,
      owner_id: user.id
    }).select().single();

    if (error) return { ok: false, message: error.message };
    await client.from("league_members").insert({ league_id: data.id, user_id: user.id });
    return { ok: true, league: data };
  }

  async function joinLeague(code) {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Sign in before joining a league." };
    const profile = await ensureProfile();
    if (!profile.ok) return profile;

    const { data: league, error: leagueError } = await client
      .from("leagues")
      .select("*")
      .eq("code", code)
      .single();

    if (leagueError) return { ok: false, message: "League code not found." };
    const { error } = await client.from("league_members").insert({ league_id: league.id, user_id: user.id });
    if (error && !error.message.includes("duplicate key")) return { ok: false, message: error.message };
    return { ok: true, league };
  }

  async function leaveLeague(leagueId) {
    const user = await getUser();
    if (!client || !user || !leagueId) return { ok: false, message: "Choose a league first." };

    const { error } = await client
      .from("league_members")
      .delete()
      .eq("league_id", leagueId)
      .eq("user_id", user.id);

    return error ? { ok: false, message: error.message } : { ok: true };
  }

  async function getLeagues() {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Not signed in." };

    const { data, error } = await client
      .from("league_members")
      .select("leagues(id,name,code,owner_id)")
      .eq("user_id", user.id);

    if (error) return { ok: false, message: error.message };
    return {
      ok: true,
      leagues: (data || []).map(row => row.leagues).filter(Boolean)
    };
  }

  async function ensureStarterLeague() {
    const user = await getUser();
    if (!client || !user) return { ok: false, message: "Sign in first." };

    const existing = await getLeagues();
    if (existing.ok && existing.leagues.length) return { ok: true, league: existing.leagues[0] };

    return createLeague("My Pundits card");
  }

  async function getPredictions(leagueId) {
    const user = await getUser();
    if (!client || !user || !leagueId) return { ok: false, message: "No league selected." };

    const [{ data: groups, error: groupError }, { data: award, error: awardError }] = await Promise.all([
      client.from("group_predictions").select("*").eq("user_id", user.id).eq("league_id", leagueId),
      client.from("award_predictions").select("*").eq("user_id", user.id).eq("league_id", leagueId).maybeSingle()
    ]);

    if (groupError) return { ok: false, message: groupError.message };
    if (awardError) return { ok: false, message: awardError.message };
    return { ok: true, groups: groups || [], award };
  }

  async function savePredictions({ leagueId, groupPicks, bonus }) {
    const user = await getUser();
    if (!client || !user || !leagueId) return { ok: false, message: "Sign in and choose a league first." };

    const groupRows = Object.entries(groupPicks).map(([groupKey, orderedTeams]) => ({
      user_id: user.id,
      league_id: leagueId,
      group_key: groupKey,
      ordered_teams: orderedTeams
    }));

    const { error: groupError } = await client
      .from("group_predictions")
      .upsert(groupRows, { onConflict: "user_id,league_id,group_key" });
    if (groupError) return { ok: false, message: groupError.message };

    const { error: bonusError } = await client.from("award_predictions").upsert({
      user_id: user.id,
      league_id: leagueId,
      champion: bonus.winner,
      top_scorer: bonus.scorer,
      top_assister: bonus.assist
    }, { onConflict: "user_id,league_id" });

    return bonusError ? { ok: false, message: bonusError.message } : { ok: true };
  }

  async function lockPredictions(leagueId) {
    const user = await getUser();
    if (!client || !user || !leagueId) return { ok: false, message: "Sign in and choose a league first." };
    const lockedAt = new Date().toISOString();

    const [{ error: groupError }, { error: awardError }] = await Promise.all([
      client.from("group_predictions").update({ locked_at: lockedAt }).eq("user_id", user.id).eq("league_id", leagueId),
      client.from("award_predictions").update({ locked_at: lockedAt }).eq("user_id", user.id).eq("league_id", leagueId)
    ]);

    if (groupError) return { ok: false, message: groupError.message };
    if (awardError) return { ok: false, message: awardError.message };
    return { ok: true, lockedAt };
  }

  async function getLeagueEntries(leagueId) {
    const user = await getUser();
    if (!client || !user || !leagueId) return { ok: false, message: "Choose a league first." };
    const picksArePublic = Date.now() >= new Date("2026-06-11T22:00:00+03:00").getTime();

    let groupQuery = client.from("group_predictions").select("*").eq("league_id", leagueId);
    let awardQuery = client.from("award_predictions").select("*").eq("league_id", leagueId);
    if (!picksArePublic) {
      groupQuery = groupQuery.eq("user_id", user.id);
      awardQuery = awardQuery.eq("user_id", user.id);
    }

    const [{ data: members, error: membersError }, { data: groups, error: groupError }, { data: awards, error: awardError }] = await Promise.all([
      client.from("league_members").select("user_id, profiles(email,squad_name)").eq("league_id", leagueId),
      groupQuery,
      awardQuery
    ]);

    if (membersError) return { ok: false, message: membersError.message };
    if (groupError) return { ok: false, message: groupError.message };
    if (awardError) return { ok: false, message: awardError.message };

    const memberRows = members || [];
    const missingProfiles = memberRows.filter(member => !member.profiles).map(member => member.user_id);
    if (missingProfiles.length) {
      const { data: profiles } = await client
        .from("profiles")
        .select("id,email,squad_name")
        .in("id", missingProfiles);
      const byId = new Map((profiles || []).map(profile => [profile.id, profile]));
      memberRows.forEach(member => {
        if (!member.profiles) member.profiles = byId.get(member.user_id) || null;
      });
    }

    return { ok: true, members: memberRows, groups: groups || [], awards: awards || [], picksArePublic };
  }

  async function getOfficialResults() {
    if (!client) return { ok: false, message: "Supabase is not configured yet." };
    const { data, error } = await client.from("official_results").select("*");
    return error ? { ok: false, message: error.message } : { ok: true, results: data || [] };
  }

  window.PunditsCloud = {
    isReady,
    signIn,
    signOut,
    getUser,
    getSession,
    waitForSession,
    getProfile,
    saveProfile,
    ensureProfile,
    createLeague,
    joinLeague,
    leaveLeague,
    getLeagues,
    ensureStarterLeague,
    getPredictions,
    savePredictions,
    lockPredictions,
    getLeagueEntries,
    getOfficialResults
  };
})();
