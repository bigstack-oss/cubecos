import { createSelector } from "reselect";

const allMailsSelector = state => state.allMails;
const filterAttrSelector = state => state.filterAttr;
const searchStringSelector = state => state.searchString;

const filterBucket = (mails, bucket) => {
	const newMails = [];
	mails.forEach(mail => {
		if (bucket === mail.bucket) {
			newMails.push(mail);
		}
	});
	return newMails;
};
const filterTag = (mails, tag) => {
	const newMails = [];
	mails.forEach(mail => {
		if (mail.tags && mail.tags.indexOf(tag) !== -1) {
			newMails.push(mail);
		}
	});
	return newMails;
};
const filterMaiil = (allMails, filterAttr, searchString) => {
	let newMails = filterBucket(allMails, filterAttr.bucket);
	if (filterAttr.tag) {
		newMails = filterTag(allMails, filterAttr.tag);
	}
	if (searchString) {
		const search = searchString.toUpperCase();
		newMails = newMails.filter(mail =>
			`${mail.email}${mail.body}${mail.subject}`.toUpperCase().includes(search)
		);
	}
	return newMails;
};

export default createSelector(
	allMailsSelector,
	filterAttrSelector,
	searchStringSelector,
	filterMaiil
);
