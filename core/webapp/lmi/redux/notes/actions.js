const notesAction = {
	CHANGE_NOTE: "CHANGE_NOTE",
	ADD_NOTE: "ADD_NOTE",
	EDIT_NOTE: "EDIT_NOTE",
	DELETE_NOTE: "DELETE_NOTE",
	CHANGE_COLOR: "CHANGE_COLOR",

	changeNote: id => {
		return (dispatch, getState) => {
			const notes = getState().Notes.notes;
			const seectedColor = notes[notes.findIndex(note => note.id === id)].color;
			dispatch({
				type: notesAction.CHANGE_NOTE,
				selectedId: id,
				seectedColor
			});
		};
	},
	addNote: () => {
		return (dispatch, getState) => {
			const newNote = {
				id: new Date().getTime(),
				note: "New Note",
				createTime: new Date(),
				color: getState().Notes.seectedColor
			};
			const notes = [newNote, ...getState().Notes.notes];
			return dispatch({
				type: notesAction.ADD_NOTE,
				selectedId: newNote.id,
				notes
			});
		};
	},
	editNote: (id, newNote) => {
		return (dispatch, getState) => {
			const oldNotes = getState().Notes.notes;
			const notes = [];
			oldNotes.forEach(note => {
				if (note.id !== id) {
					notes.push(note);
				} else {
					note.note = newNote;
					notes.push(note);
				}
			});
			dispatch({
				type: notesAction.EDIT_NOTE,
				notes
			});
		};
	},
	deleteNote: id => {
		return (dispatch, getState) => {
			const oldNotes = getState().Notes.notes;
			const notes = [];
			oldNotes.forEach(note => {
				if (note.id !== id) {
					notes.push(note);
				}
			});
			let selectedId = getState().Notes.selectedId;
			if (selectedId === id) {
				if (notes.length === 0) {
					selectedId = undefined;
				} else {
					selectedId = notes[0].id;
				}
			}
			dispatch({
				type: notesAction.DELETE_NOTE,
				notes,
				selectedId
			});
		};
	},
	changeColor: seectedColor => {
		return (dispatch, getState) => {
			const oldNotes = getState().Notes.notes;
			const selectedId = getState().Notes.selectedId;
			const notes = [];
			oldNotes.forEach(note => {
				if (note.id !== selectedId) {
					notes.push(note);
				} else {
					note.color = seectedColor;
					notes.push(note);
				}
			});
			dispatch({
				type: notesAction.CHANGE_COLOR,
				notes,
				seectedColor
			});
		};
	}
};
export default notesAction;
