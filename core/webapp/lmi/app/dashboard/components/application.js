// dashboard/components/application.js
import React, { Component } from 'react';
import throttle from 'lodash/throttle';
import FlipMove from 'react-flip-move';
import Toggle from './toggle.js';
import IntlMessages from '../../../components/utility/intlMessages';
import { SingleCardWrapper, SortableCardWrapper } from './application-style.js';

class ListItem extends Component {
  render() {
    const listClass = `isoSingleCard card ${this.props.view}`;
    const style = { zIndex: 100 - this.props.index };

    return (
      <SingleCardWrapper id={this.props.NAME} className={listClass} style={style}>
        <div className="isoCardImage">
          <a href={this.props.LINK} target='_blank'>
            <img alt={this.props.IMAGE} src={`/static/image/app/${this.props.IMAGE}`} />
          </a>
        </div>
        <div className="isoCardContent">
          <a href={this.props.LINK} target='_blank'>
            <h3 className="isoCardTitle">{this.props.NAME}</h3>
            <span className="isoCardLink">
              {this.props.LINK}
            </span>
          </a>
        </div>
      </SingleCardWrapper>
    );
  }
}

class Application extends Component {
  constructor(props) {
    super(props);

    const { groups } = props;

    let g = [ 'all' ];
    if (groups) {
      if (typeof groups == 'string')
        g.push(groups);
      else
        g = g.concat(groups);
    }

    let apps = [];
    for (var i = 0; i < g.length; i++) {
      const items = window.app[g[i]];
      if (!items)
        continue;

      for (var j = 0; j < items.length; j++) {
        let found = false;
        for (var k = 0; k < apps.length; k++) {
          if (apps[k].NAME == items[j].NAME) {
            found = true;
            break;
          }
        }
        if (!found)
          apps.push(items[j]);
      }
    }

    this.state = {
      removedApps: [],
      view: 'grid',
      order: 'asc',
      sortingMethod: 'chronological',
      enterLeaveAnimation: 'accordionVertical',
      Apps: apps,
    };

    this.toggleList = this.toggleList.bind(this);
    this.toggleGrid = this.toggleGrid.bind(this);
    this.toggleSort = this.toggleSort.bind(this);
    this.sortRotate = this.sortRotate.bind(this);
  }

  toggleList() {
    this.setState({
      view: 'list',
      enterLeaveAnimation: 'accordionVertical',
    });
  }

  toggleGrid() {
    this.setState({
      view: 'grid',
      enterLeaveAnimation: 'accordionHorizontal',
    });
  }

  toggleSort() {
    const sortAsc = (a, b) => ('' + a.NAME).localeCompare(b.NAME);
    const sortDesc = (a, b) => ('' + b.NAME).localeCompare(a.NAME);

    this.setState({
      order: this.state.order === 'asc' ? 'desc' : 'asc',
      sortingMethod: 'chronological',
      Apps: this.state.Apps.sort(
        this.state.order === 'asc' ? sortDesc : sortAsc
      ),
    });
  }

  sortShuffle() {
    this.setState({
      sortingMethod: 'shuffle',
      Apps: shuffle(this.state.Apps),
    });
  }

  moveApp(source, dest, id) {
    const sourceApps = this.state[source].slice();
    let destApps = this.state[dest].slice();

    if (!sourceApps.length) return;

    // Find the index of the App clicked.
    // If no ID is provided, the index is 0
    const i = id ? sourceApps.findIndex(App => App.NAME === NAME) : 0;

    // If the App is already removed, do nothing.
    if (i === -1) return;

    destApps = [].concat(sourceApps.splice(i, 1), destApps);

    this.setState({
      [source]: sourceApps,
      [dest]: destApps,
    });
  }

  sortRotate() {
    const Apps = this.state.Apps.slice();
    Apps.unshift(Apps.pop());

    this.setState({
      sortingMethod: 'rotate',
      Apps,
    });
  }

  renderApps() {
    return this.state.Apps.map((App, i) => {
      return (
        <ListItem
          key={i}
          index={i}
          view={this.state.view}
          clickHandler={throttle(
            () => this.moveApp('Apps', 'removedApps', App.Name),
            800
          )}
          {...App}
        />
      );
    });
  }

  render() {
    return (
      <SortableCardWrapper
        id="shuffle"
        className={`isomorphicSortableCardsHolder ${this.state.view}`}
      >
        <header className="isoControlBar">
          <div className="isoViewBtnGroup">
            <Toggle
              clickHandler={this.toggleList}
              text={<IntlMessages id="toggle.list" />}
              icon="bars"
              active={this.state.view === 'list'}
            />
            <Toggle
              clickHandler={this.toggleGrid}
              text={<IntlMessages id="toggle.grid" />}
              icon="appstore"
              active={this.state.view === 'grid'}
            />
          </div>

          <div className="isoControlBtnGroup">
            <Toggle
              clickHandler={this.toggleSort}
              text={
                this.state.order === 'asc' ? (
                  <IntlMessages id="toggle.ascending" />
                ) : (
                  <IntlMessages id="toggle.descending" />
                )
              }
              icon={this.state.order === 'asc' ? 'up' : 'down'}
              active={this.state.sortingMethod === 'chronological'}
            />
            <Toggle
              clickHandler={this.sortRotate}
              text={<IntlMessages id="toggle.rotate" />}
              icon="reload"
              active={this.state.sortingMethod === 'rotate'}
            />
          </div>
        </header>

        <div className="isoSortableCardsContainer">
          <FlipMove
            staggerDurationBy="30"
            duration={500}
            enterAnimation={this.state.enterLeaveAnimation}
            leaveAnimation={this.state.enterLeaveAnimation}
            typeName="ul"
          >
            {this.renderApps()}
          </FlipMove>
        </div>
      </SortableCardWrapper>
    );
  }
}

export default Application;
