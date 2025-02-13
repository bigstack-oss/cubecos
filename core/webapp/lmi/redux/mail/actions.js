const mailActions = {
	FILTER_ATTRIBUTE: "FILTER_ATTRIBUTE",
	SELECTED_MAIL: "SELECTED_MAIL",
	COMPOSE_MAIL: "COMPOSE_MAIL",
	REPLY_MAIL: "REPLY_MAIL",
	SEARCH_STRING: "SEARCH_STRING",
	filterAction: newFilterAttr => {
		return (dispatch, getState) => {
			const filterAttr = getState().Mails.filterAttr;
			if (newFilterAttr) {
				if (newFilterAttr.bucket) {
					filterAttr.bucket = newFilterAttr.bucket;
					filterAttr.tag = newFilterAttr.tag;
				} else if (newFilterAttr.tag) {
					filterAttr.tag = newFilterAttr.tag;
				}
			}
			dispatch({
				type: mailActions.FILTER_ATTRIBUTE,
				filterAttr
			});
		};
	},
	selectMail: selectedMail => {
		return (dispatch, getState) => {
			const allMails = getState().Mails.allMails;
			allMails[
				allMails.findIndex(mail => mail.id === selectedMail)
			].read = true;
			dispatch({
				type: mailActions.SELECTED_MAIL,
				selectedMail,
				allMails
			});
		};
	},
	changeComposeMail: composeMail => ({
		type: mailActions.COMPOSE_MAIL,
		composeMail
	}),
	changeReplyMail: replyMail => ({
		type: mailActions.REPLY_MAIL,
		replyMail
	}),
	changeSearchString: searchString => ({
		type: mailActions.SEARCH_STRING,
		searchString
	})
};
export default mailActions;
