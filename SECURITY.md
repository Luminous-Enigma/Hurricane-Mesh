# Security and privacy

## Do not post personal information

This is a public repository. Anything posted in an issue, pull request, or discussion can
be read by anyone and stays in search engines and archives, even after it is deleted.

**Never post:**

- photos or screenshots of real letters, notices, or documents
- real addresses, locations, or GPS coordinates
- real names, phone numbers, or emails (yours or anyone else's)
- radio channel keys, PSKs, or QR codes for a channel
- Meshtastic node IDs tied to a real person
- signing keys, API tokens, passwords, or `.env` files

If you need to show a problem, use made-up data ("Jane Example, 123 Sample St").
If you post something by mistake, edit it out right away and tell the maintainer so it can
be removed from the history.

## Reporting a security problem privately

**Do not open a public issue for a security problem.**

Use GitHub's private reporting: open the repository's **Security** tab and choose
**Report a vulnerability**. Only the maintainer can see the report.

Please include:

- what the problem is and what someone could do with it
- steps to reproduce it, using made-up data only
- the app version or commit, and the phone model and Android version if relevant

You should get a reply within 7 days. Please give the maintainer reasonable time to fix
the problem before you talk about it publicly.

## In scope

- anything that leaks a family channel key, an exact location, or another private detail
  onto the mesh or off the device
- anything that lets a forked pull request reach repository secrets
- spoofing that makes a post look official or verified in the app

## Not in scope

- The fact that anyone can post on the open Block channel. That is how a mesh works, and
  the app labels every post as unverified.
- Problems in Meshtastic firmware or radios. Report those to the
  [Meshtastic project](https://github.com/meshtastic).
