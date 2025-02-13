import React, { Component } from "react";
import { connect } from "react-redux";
import Toolbar from "../../components/uielements/toolbar";
import Icon from "../../components/uielements/icon";
import MenuIcon from "material-ui-icons/Menu";
import appActions from "../../redux/app/actions";
import themeActions from "../../redux/themeSwitcher/actions";
import { AppHolder, IconButtons, TopbarComponents } from "./style";
import TopbarSearch from "./topbarSearch";
import SecondarySidebar from "../SecondarySidebar";
import ThemeSwitcher from "../ThemeSwitcher";
import TopbarNotification from "./topbarNotification";
import TopbarUser from "./topbarUser";
const { toggleCollapsed } = appActions;
const { switchActivation } = themeActions;

class Topbar extends Component {
	render() {
		const {
			toggleCollapsed,
			collapsed,
			locale,
			url,
			customizedTheme,
			switchActivation
		} = this.props;
		const propsTopbar = { locale, url };
		return (
			<AppHolder
				className={collapsed ? "collapsed" : ""}
				style={{ background: customizedTheme.backgroundColor }}
			>
				<Toolbar
					style={{
						paddingLeft: "30px",
						minHeight: "64px",
						background: customizedTheme.topbarTheme
					}}
				>
					<IconButtons
						id="topbarCollapsed"
						aria-label="open drawer"
						onClick={toggleCollapsed}
						className="isoRight"
					>
						<MenuIcon />
					</IconButtons>

					<TopbarComponents>
						<ul className="topbarItems">
							<li className="topbarSearch">
								<TopbarSearch {...propsTopbar} />
							</li>

							{/* <li className="topbarNotification">
                <TopbarNotification {...propsTopbar} />
              </li> */}
							<li className="topbarNotification">
								<div>
									<Icon onClick={() => switchActivation("notification")}>
										notifications_active
									</Icon>
									<SecondarySidebar
										InnerComponent={TopbarNotification}
										currentActiveKey="notification"
									/>
								</div>
							</li>

							<li className="topbarNotification">
								<div>
									<Icon onClick={() => switchActivation("themeSwitcher")}>
										settings
									</Icon>
									<SecondarySidebar
										InnerComponent={ThemeSwitcher}
										currentActiveKey="themeSwitcher"
									/>
								</div>
							</li>

							<li className="topbarUser">
								<TopbarUser {...propsTopbar} />
							</li>
						</ul>
					</TopbarComponents>
				</Toolbar>
			</AppHolder>
		);
	}
}

export default connect(
	state => ({
		...state.App,
		locale: state.LanguageSwitcher.language.locale,
		customizedTheme: state.ThemeSwitcher.topbarTheme
	}),
	{ toggleCollapsed, switchActivation }
)(Topbar);
