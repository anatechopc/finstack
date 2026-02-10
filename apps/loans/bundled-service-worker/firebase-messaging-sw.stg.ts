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
  apiKey: 'AIzaSyD1iInYsqJSpVjgbJEl1GC-oZRKXZ0n3lA',
  appId: '1:565409367468:web:56eb0d413e9adfe58fe609',
  messagingSenderId: '565409367468',
  projectId: 'loooans-dev-stg',
  authDomain: 'loooans-dev-stg.firebaseapp.com',
  databaseURL: 'https://loooans-dev-stg-default-rtdb.asia-southeast1.firebasedatabase.app',
  storageBucket: 'loooans-dev-stg.appspot.com',
  measurementId: 'G-DWEXQFQ26Z',
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
