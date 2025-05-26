#  Subscription manual smoke tests

### Common:
- Search for "privacy pro" in DDG and open the /pro link: it should intercept and open the purchase flow
- (on Mac) with active subscription, open welcome page, DBP, ITR and FAQ tabs, sign out: all tabs are closed automatically

### App store:
- Buy 
- Remove from device
- Cancel in the middle of buying 
- Simulate an error while buying (in code)
- Restore successfully
- Restore inexistent subscription
- After purchase, sign out and try to buy again
- Add another email
- Manage email > Remove
- When purchased, remove from device and attempt purchase again: shows alert suggesting to restore
- Restore when the subscription is expired: triggers the "view plans" prompt

### Stripe:
- Buy
- Remove
- Restore successfully
- Add another email
- Manage email > Remove 
