//
//  BasicFetchedResultsTableViewController.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 23.02.24.
//  Copyright (c) 2024 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import AmperfyKit
import CoreData
import UIKit

class BasicFetchedResultsTableViewController<ResultType>: BasicTableViewController
  where ResultType: NSFetchRequestResult {
  var isIndexTitelsHidden = false

  private var singleFetchController: BasicFetchedResultsController<ResultType>?
  var singleFetchedResultsController: BasicFetchedResultsController<ResultType>? {
    set { singleFetchController = newValue }
    get { singleFetchController }
  }

  /// Space between a section and the header of the next one. The table's own padding above
  /// section headers is turned off, as it would also push the first header away from the
  /// play/shuffle header; the space is added inside the headers of the following sections.
  static var sectionHeaderSpacing: CGFloat { 22 }

  /// Off for screens with their own section header views, which rely on the table's padding
  var usesSectionHeaderSpacing: Bool { true }

  override func viewIsAppearing(_ animated: Bool) {
    // only tables with the default header views (see `viewForHeaderInSection`) add the space
    // back; set before super, which reloads the results
    if usesSectionHeaderSpacing, tableView.separatorStyle == .none {
      tableView.sectionHeaderTopPadding = 0
    }
    super.viewIsAppearing(animated)
  }

  override func sectionHeaderTopInset(forSection section: Int) -> CGFloat {
    guard section > 0, tableView.sectionHeaderTopPadding == 0 else { return 0 }
    return Self.sectionHeaderSpacing
  }

  /// Height of a section header with title, including the space to the previous section
  func sectionHeaderHeight(forSection section: Int) -> CGFloat {
    CommonScreenOperations.tableSectionHeightLarge + sectionHeaderTopInset(forSection: section)
  }

  override func numberOfSections(in tableView: UITableView) -> Int {
    singleFetchController?.numberOfSections ?? 0
  }

  override func tableView(
    _ tableView: UITableView,
    titleForHeaderInSection section: Int
  )
    -> String? {
    singleFetchController?.titleForHeader(inSection: section)
  }

  /// Lists grouped by initial letter show the letter above each section, so it is also visible
  /// after a jump via the section index. Screens with other groupings decide themselves.
  override func tableView(
    _ tableView: UITableView,
    heightForHeaderInSection section: Int
  )
    -> CGFloat {
    guard singleFetchController?.fetchResultsController.sectionIndexType == .alphabet,
          let title = self.tableView(tableView, titleForHeaderInSection: section), !title.isEmpty
    else { return 0.0 }
    return sectionHeaderHeight(forSection: section)
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    singleFetchController?.numberOfRows(inSection: section) ?? 0
  }

  override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
    isIndexTitelsHidden ? nil : singleFetchController?.sectionIndexTitles
  }

  override func tableView(
    _ tableView: UITableView,
    sectionForSectionIndexTitle title: String,
    at index: Int
  )
    -> Int {
    singleFetchController?.section(forSectionIndexTitle: title, at: index) ?? 0
  }
}
