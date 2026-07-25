//
//  ListView.swift
//  Containers
//
//  Created by Axel Martinez on 30/05/2026.
//

import ContainerSystem
import SwiftUI

struct ListView<RowValue, Columns>: View
where RowValue: Identifiable, Columns: TableColumnContent<RowValue, Never> {
    @Environment(SystemManager.self) private var system

    let rows: [RowValue]
    let refreshTrigger: Int
    let lastUpdated: Date?
    let isFiltering: Bool
    let tableStyle: ListTableStyle
    let onClear: @MainActor () -> Void
    let onRefresh: @MainActor () async -> Void
    let columns: Columns

    init(
        rows: [RowValue],
        refreshTrigger: Int,
        lastUpdated: Date?,
        isFiltering: Bool,
        tableStyle: ListTableStyle = .inset,
        onClear: @escaping @MainActor () -> Void,
        onRefresh: @escaping @MainActor () async -> Void,
        @TableColumnBuilder<RowValue, Never> columns: () -> Columns
    ) {
        self.rows = rows
        self.refreshTrigger = refreshTrigger
        self.lastUpdated = lastUpdated
        self.isFiltering = isFiltering
        self.tableStyle = tableStyle
        self.onClear = onClear
        self.onRefresh = onRefresh
        self.columns = columns()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if system.status == .running {
                styledTable
            } else {
                SystemStatusView()
            }
        }
        .onChange(of: system.status, initial: true) {
            guard system.status == .running else {
                onClear()
                return
            }

            Task {
                guard lastUpdated == nil else { return }
                await onRefresh()
            }
        }
        .onChange(of: refreshTrigger) {
            Task {
                await onRefresh()
            }
        }
        .onAppear {
            Task {
                guard system.status == .running else { return }
                await onRefresh()
            }
        }
    }

    @ViewBuilder
    private var styledTable: some View {
        switch tableStyle {
        case .automatic:
            table
                .tableStyle(.automatic)
        case .inset:
            table
                .tableStyle(.inset)
        }
    }

    private var table: some View {
        Table(
            of: RowValue.self,
            columns: { columns },
            rows: { ForEach(rows) }
        )
    }
}

enum ListTableStyle {
    case automatic
    case inset
}
