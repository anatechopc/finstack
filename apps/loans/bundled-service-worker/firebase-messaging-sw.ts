import { initializeApp } from 'firebase/app';
import {
  experimentalSetDeliveryMetricsExportedToBigQueryEnabled,
  getMessaging,
  isSupported,
  onBackgroundMessage
} from 'firebase/messaging/sw';

declare var self: ServiceWorkerGlobalScope;

self.addEventListener('install', (event) => {
  console.log(self);
  console.log(event);
});

const app = initializeApp({
  apiKey: 'AIzaSyATaPKWgNzIa9H1w_07VmSS42DPnHwxRZk',
  appId: '1:444559784514:web:be09bfc7525b4d7677cbdb',
  messagingSenderId: '444559784514',
  projectId: 'loooans-prod',
  authDomain: 'loooans-prod.firebaseapp.com',
  databaseURL: 'https://loooans-prod-default-rtdb.asia-southeast1.firebasedatabase.app',
  storageBucket: 'loooans-prod.appspot.com',
  measurementId: 'G-ZPYS3RCP3W',
});

isSupported().then((isSupported) => {
  if (isSupported) {
    const messaging = getMessaging(app);

    // experimentalSetDeliveryMetricsExportedToBigQueryEnabled(messaging, true);

    onBackgroundMessage(messaging, ({ notification: notification }) => {
      const { title, body, image } = notification ?? {};

      if (!title) {
        return;
      }

      self.registration.showNotification(title, {
        body,
        icon: image || '/assets/icons/logo-72x72.png',
      });
    });
  }
});
