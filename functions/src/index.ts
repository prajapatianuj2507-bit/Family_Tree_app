import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

function formatShortDateTime(date: Date): string {
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Asia/Kolkata",
  });
}

// ── TRIGGERED ON EVENT CREATION ──────────────────────────────────────────
export const onFamilyEventCreated = functions.firestore
  .document("families/{familyId}/events/{eventId}")
  .onCreate(async (snapshot, context) => {
    const eventData = snapshot.data();
    if (!eventData) {
      console.log("No document data found for the event trigger.");
      return;
    }

    const eventId = context.params.eventId;
    const familyId = context.params.familyId;
    const createdBy = eventData.createdBy;
    const title = eventData.title || "New Family Event";
    const description = eventData.description || "";

    const startTimestamp = eventData.startDateTime;
    const startDate = startTimestamp && startTimestamp.toDate ? startTimestamp.toDate() : new Date(startTimestamp);
    const formattedStart = formatShortDateTime(startDate);

    const body = description.length > 120 
      ? `${description.substring(0, 117)}...` 
      : description;

    const db = admin.firestore();

    try {
      // 1. Fetch family details
      const familyDoc = await db.collection("families").doc(familyId).get();
      const familyName = familyDoc.exists ? (familyDoc.data()?.familyName || "Unknown Family") : "Unknown Family";

      // 2. Write in-app notification for the family (recipientId: null)
      await db.collection("notifications").add({
        familyId: familyId,
        recipientId: null,
        type: "event_created",
        title: "New Family Event",
        body: `"${title}" is scheduled for ${formattedStart}.`,
        eventId: eventId,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // 3. Write in-app notification for the Master (recipientId: "master", including familyName)
      await db.collection("notifications").add({
        familyId: familyId,
        familyName: familyName,
        recipientId: "master",
        type: "event_created",
        title: `New Event in ${familyName}`,
        body: `"${title}" was scheduled by family "${familyName}" for ${formattedStart}.`,
        eventId: eventId,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
      });

      // 4. Retrieve FCM tokens for both family members and master users
      const tokensSnap = await db.collection("fcm_tokens").where("familyId", "==", familyId).get();
      const masterTokensSnap = await db.collection("fcm_tokens").where("familyId", "==", "master").get();

      const messages: admin.messaging.Message[] = [];

      // Add messages for family members (excluding creator)
      tokensSnap.forEach((doc) => {
        const data = doc.data();
        if (data.token && data.memberId !== createdBy) {
          messages.push({
            token: data.token,
            notification: {
              title: title,
              body: body,
            },
            data: {
              eventId: eventId,
              familyId: familyId,
              type: "FAMILY_EVENT"
            }
          });
        }
      });

      // Add messages for Master users (with Family Name)
      masterTokensSnap.forEach((doc) => {
        const data = doc.data();
        if (data.token) {
          messages.push({
            token: data.token,
            notification: {
              title: `[${familyName}] New Event: ${title}`,
              body: `${body} (Family: ${familyName})`,
            },
            data: {
              eventId: eventId,
              familyId: familyId,
              type: "FAMILY_EVENT"
            }
          });
        }
      });

      if (messages.length > 0) {
        const response = await admin.messaging().sendEach(messages);
        console.log(`Sent FCM notifications to ${response.successCount} devices.`);

        // Stale token cleanup
        if (response.failureCount > 0) {
          const deleteOps: Promise<any>[] = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success && resp.error) {
              const code = resp.error.code;
              if (
                code === "messaging/invalid-registration-token" ||
                code === "messaging/registration-token-not-registered"
              ) {
                const staleToken = (messages[idx] as admin.messaging.TokenMessage).token;
                deleteOps.push(db.collection("fcm_tokens").doc(staleToken).delete());
              }
            }
          });
          if (deleteOps.length > 0) {
            await Promise.all(deleteOps);
            console.log(`Cleaned up ${deleteOps.length} obsolete tokens.`);
          }
        }
      }
    } catch (error) {
      console.error(`Error broadcasting FCM notification for event ${eventId}:`, error);
    }
  });

// ── TRIGGERED ON MEMBER CREATION ──────────────────────────────────────────
export const onMemberCreated = functions.firestore
  .document("members/{memberId}")
  .onCreate(async (snapshot, context) => {
    const memberData = snapshot.data();
    if (!memberData) {
      console.log("No document data found for the member trigger.");
      return;
    }

    const memberId = context.params.memberId;
    const email = memberData.authEmail || (memberData.mobileNumber ? `${memberData.mobileNumber.trim()}@familytree.internal` : null);
    const password = memberData.password;

    if (!email || !password) {
      console.log(`Missing email or password for member ${memberId}. Skipping Auth creation.`);
      return;
    }

    try {
      try {
        await admin.auth().getUser(memberId);
        console.log(`Auth user for member ${memberId} already exists.`);
        return;
      } catch (authErr: any) {
        if (authErr.code !== "auth/user-not-found") {
          throw authErr;
        }
      }

      await admin.auth().createUser({
        uid: memberId,
        email: email,
        password: password,
      });
      console.log(`Successfully created Auth user for member ${memberId} via Firestore trigger.`);
    } catch (error) {
      console.error(`Error creating Auth user for member ${memberId}:`, error);
    }
  });

// ── SCHEDULED REMINDER FUNCTION ──────────────────────────────────────────
export const sendEventReminders = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async (context) => {
    const db = admin.firestore();
    const now = Date.now();

    try {
      const eventsSnap = await db.collectionGroup("events").get();
      console.log(`Checking reminders for ${eventsSnap.size} events.`);

      for (const eventDoc of eventsSnap.docs) {
        const eventData = eventDoc.data();
        if (!eventData) continue;

        const eventId = eventDoc.id;
        const familyId = eventData.familyId || (eventDoc.ref.parent && eventDoc.ref.parent.parent ? eventDoc.ref.parent.parent.id : "");
        if (!familyId) continue;

        const startTimestamp = eventData.startDateTime;
        const start = startTimestamp && startTimestamp.toDate ? startTimestamp.toDate().getTime() : new Date(startTimestamp).getTime();
        const created = eventData.createdAt
          ? (eventData.createdAt.toDate ? eventData.createdAt.toDate().getTime() : new Date(eventData.createdAt).getTime())
          : 0; // default to epoch 0 for legacy events so advanceTime is large

        const advanceTime = start - created;
        const timeUntilStart = start - now;
        const remindersSent = eventData.remindersSent || {};

        console.log(`Event ${eventId} (${eventData.title}): timeUntilStart=${(timeUntilStart / 1000 / 60 / 60).toFixed(2)}h, advanceTime=${(advanceTime / 1000 / 60 / 60).toFixed(2)}h, remindersSent=${JSON.stringify(remindersSent)}`);

        // Skip events that already started
        if (timeUntilStart <= 0) continue;

        const title = eventData.title || "Upcoming Event";

        let milestoneToTrigger: string | null = null;
        let hoursLabel = "";
        const updates: Record<string, boolean> = {};

        // Check milestones:
        // 2 hours: Created >= 2h prior, starts within 2h, not yet sent
        if (timeUntilStart <= 2 * 60 * 60 * 1000) {
          if (advanceTime >= 2 * 60 * 60 * 1000 && !remindersSent["2h"]) {
            milestoneToTrigger = "2h";
            hoursLabel = "2 hours";
          }
          updates["remindersSent.2h"] = true;
          updates["remindersSent.24h"] = true;
          updates["remindersSent.48h"] = true;
        }
        // 24 hours: Created >= 24h prior, starts within 24h, not yet sent
        else if (timeUntilStart <= 24 * 60 * 60 * 1000) {
          if (advanceTime >= 24 * 60 * 60 * 1000 && !remindersSent["24h"]) {
            milestoneToTrigger = "24h";
            hoursLabel = "24 hours";
          }
          updates["remindersSent.24h"] = true;
          updates["remindersSent.48h"] = true;
        }
        // 48 hours: Created >= 48h prior, starts within 48h, not yet sent
        else if (timeUntilStart <= 48 * 60 * 60 * 1000) {
          if (advanceTime >= 48 * 60 * 60 * 1000 && !remindersSent["48h"]) {
            milestoneToTrigger = "48h";
            hoursLabel = "48 hours";
          }
          updates["remindersSent.48h"] = true;
        }

        if (milestoneToTrigger) {
          console.log(`Triggering ${milestoneToTrigger} reminder for event ${eventId} in family ${familyId}.`);

          // 1. Mark reminder as sent/skipped immediately to avoid double sends
          await eventDoc.ref.update(updates);

          // 2. Fetch family details
          const familyDoc = await db.collection("families").doc(familyId).get();
          const familyName = familyDoc.exists ? (familyDoc.data()?.familyName || "Unknown Family") : "Unknown Family";

          // 3. Write in-app notifications
          // Family-side
          await db.collection("notifications").add({
            familyId: familyId,
            recipientId: null,
            type: "event_reminder",
            title: `Event Reminder: ${title}`,
            body: `"${title}" starts in ${hoursLabel}!`,
            eventId: eventId,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });

          // Master-side
          await db.collection("notifications").add({
            familyId: familyId,
            familyName: familyName,
            recipientId: "master",
            type: "event_reminder",
            title: `Event Reminder in ${familyName}`,
            body: `"${title}" in family "${familyName}" starts in ${hoursLabel}.`,
            eventId: eventId,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
          });

          // 4. Send FCM alerts
          const fcmTokens: string[] = [];
          const masterTokens: string[] = [];

          const tokensSnap = await db.collection("fcm_tokens").where("familyId", "==", familyId).get();
          tokensSnap.forEach((doc) => {
            const t = doc.data().token;
            if (t) fcmTokens.push(t);
          });

          const masterTokensSnap = await db.collection("fcm_tokens").where("familyId", "==", "master").get();
          masterTokensSnap.forEach((doc) => {
            const t = doc.data().token;
            if (t) masterTokens.push(t);
          });

          const messages: admin.messaging.Message[] = [];

          // Add messages for family members
          fcmTokens.forEach((token) => {
            messages.push({
              token: token,
              notification: {
                title: `Upcoming Event: ${title}`,
                body: `Starts in ${hoursLabel}!`,
              },
              data: {
                eventId: eventId,
                familyId: familyId,
                type: "EVENT_REMINDER"
              }
            });
          });

          // Add messages for Master (with family name)
          masterTokens.forEach((token) => {
            messages.push({
              token: token,
              notification: {
                title: `[${familyName}] Reminder: ${title}`,
                body: `Starts in ${hoursLabel}! (Family: ${familyName})`,
              },
              data: {
                eventId: eventId,
                familyId: familyId,
                type: "EVENT_REMINDER"
              }
            });
          });

          if (messages.length > 0) {
            const response = await admin.messaging().sendEach(messages);
            console.log(`Sent ${response.successCount} reminder push notifications.`);

            if (response.failureCount > 0) {
              const deleteOps: Promise<any>[] = [];
              response.responses.forEach((resp, idx) => {
                if (!resp.success && resp.error) {
                  const code = resp.error.code;
                  if (
                    code === "messaging/invalid-registration-token" ||
                    code === "messaging/registration-token-not-registered"
                  ) {
                    const staleToken = (messages[idx] as admin.messaging.TokenMessage).token;
                    deleteOps.push(db.collection("fcm_tokens").doc(staleToken).delete());
                  }
                }
              });
              if (deleteOps.length > 0) {
                await Promise.all(deleteOps);
              }
            }
          }
        }
      }
    } catch (err) {
      console.error("Error running sendEventReminders scheduled function:", err);
    }
  });
