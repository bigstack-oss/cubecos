import { combineReducers } from 'redux';
import Auth from './auth/reducer';
import App from './app/reducer';
import Mails from './mail/reducer';
import Calendar from './calendar/reducer';
import Notes from './notes/reducer';
import Todos from './todos/reducer';
import Contacts from './contacts/reducer';
import Cards from './card/reducer';
import Chat from './chat/reducers';
import Invoices from './invoice/reducer';
import Ecommerce from './ecommerce/reducer';
import ThemeSwitcher from './themeSwitcher/reducer';
import LanguageSwitcher from './languageSwitcher/reducer';
import YoutubeSearch from './youtubeSearch/reducers';
import githubSearch from './githubSearch/reducers';
// import DevReducers from '../customApp/redux/reducers';

export default combineReducers({
	Auth,
	App,
	ThemeSwitcher,
	LanguageSwitcher,
	Mails,
	Calendar,
	YoutubeSearch,
	githubSearch,
	Cards,
	Ecommerce,
	Notes,
	Todos,
	Contacts,
	Chat,
	Invoices,
	// ...DevReducers
});
