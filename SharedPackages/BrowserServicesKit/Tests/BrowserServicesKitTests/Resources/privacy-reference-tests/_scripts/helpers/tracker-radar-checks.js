/**
 * Basic sanity checks for Tracker Radar blocklists. Those are usually crafted by hend for purpose of testing and can have errors.
 * 
 * @param {{trackers: Object<string, any>, entities: Object<string, any>, domains: Object<string, string>}} trackerRadarObject 
 * @returns {Array<{message:string, location: string}>}
 */
module.exports = (trackerRadarObject) => {
    const errors = [];

    function error(message, ...location) {
        errors.push({message, location: location.join(' ↣ ')});
    }

    Object.keys(trackerRadarObject.trackers).forEach(domain => {
        const tracker = trackerRadarObject.trackers[domain];

        if (tracker.domain !== domain) {
            error('"domain" value doesn\'t match key value', 'trackers', domain);
        }

        const trackersOwnerName = tracker.owner.name;

        if (!trackerRadarObject.entities[trackersOwnerName]) {
            error('owner name missing from "entities" object', 'trackers', domain);
        } else {
            if (!trackerRadarObject.entities[trackersOwnerName].domains.includes(domain)) {
                error(`missing domain: ${domain}`, 'entities', trackersOwnerName);
            }
        }

        const entityOwners = Object.keys(trackerRadarObject.entities).filter(owner => trackerRadarObject.entities[owner].domains.includes(domain));

        if (entityOwners.length > 1) {
            error(`${domain} has multiple owners`, 'entities', entityOwners[0]);
        }

        const domainsOwnerName = trackerRadarObject.domains[domain];

        if (!domainsOwnerName) {
            error('domain missing form "domains" object', 'trackers', domain);
        } else {
            if (domainsOwnerName !== trackersOwnerName) {
                error('owner name doesn\'t match name of the owner in "domains" object', 'trackers', domain);
            }
        }
    });

    return errors;
}