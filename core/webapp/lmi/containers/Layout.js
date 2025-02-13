import React, { Component } from "react";
import { connect } from "react-redux";
import WindowResizeListener from "react-window-size-listener";
import { Debounce } from "react-throttle";
import { Layout } from "antd";
import { ThemeProvider } from "styled-components";
import { initGA, logPageView } from "../helpers/analytics";
import themes from "../config/themes";
import { siteConfig } from "../config/index";
import authAction from "../redux/auth/actions";
import appActions from "../redux/app/actions";
import AppLocale from "../languageProvider";

const { logout } = authAction;
const { toggleAll } = appActions;
const { Content, Footer } = Layout;

class Header extends Component {
	render() {
		const { selectedTheme } = this.props;
		if (this.props.App.height === 0) {
			return (
				<div>
					<Debounce time="1000" handler="onResize">
						<WindowResizeListener
							onResize={windowSize =>
								this.props.toggleAll(
									windowSize.windowWidth,
									windowSize.windowHeight
								)
							}
						/>
					</Debounce>
				</div>
			);
		}
		return (
			<div>
				<header>
					<ThemeProvider theme={themes[selectedTheme]}>
						{this.props.children}
					</ThemeProvider>
				</header>
			</div>
		);
	}
}
const mapStateToProps = state => ({
	auth: state.Auth,
	App: state.App,
	selectedTheme: state.ThemeSwitcher.changeThemes.themeName
});
export default connect(mapStateToProps, { logout, toggleAll })(Header);
